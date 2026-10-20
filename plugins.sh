#!/usr/bin/env bash
# Manage the plugin JARs in ./plugins using the versions pinned in plugins.json.
#
#   ./plugins.sh add X    add a plugin by Modrinth slug or URL, pin it and download it
#   ./plugins.sh remove X remove a plugin from the lockfile and delete its JAR
#   ./plugins.sh check    report available updates, change nothing
#   ./plugins.sh update   pin the newest compatible versions, then sync
#   ./plugins.sh sync     download and verify the pinned JARs (no API lookups)
set -euo pipefail
cd "$(dirname "$0")"

LOCK="plugins.json"
PLUGINS_DIR="plugins"
API="https://api.modrinth.com/v2"
USER_AGENT="ivanbratovic/papermc-deployment (plugins.sh)"

MODE="${1:-}"
TARGET="${2:-}"
ONLY=""
case "$MODE" in
    check|update|sync) ;;
    add|remove) [ -n "$TARGET" ] || { echo "Usage: $0 $MODE <slug|modrinth-url>"; exit 1; } ;;
    *) echo "Usage: $0 add|remove <slug|modrinth-url>|check|update|sync"; exit 1 ;;
esac

resolve() {
    # Pin the newest compatible Modrinth version of every plugin with a slug
    local minecraft_version count i entry slug old_version old_file channel versions latest new_version
    minecraft_version=$(grep -E '^MINECRAFT_VERSION=' .env | cut -d= -f2)
    [ -n "$minecraft_version" ] || { echo "MINECRAFT_VERSION not found in .env"; exit 1; }

    count=$(jq '.plugins | length' "$LOCK")
    for i in $(seq 0 $((count - 1))); do
        entry=$(jq -c ".plugins[$i]" "$LOCK")
        slug=$(jq -r '.slug // empty' <<< "$entry")
        # Entries without a slug are direct-URL plugins, managed by hand
        [ -n "$slug" ] || continue
        [ -z "$ONLY" ] || [ "$slug" = "$ONLY" ] || continue

        old_version=$(jq -r '.version // "none"' <<< "$entry")
        old_file=$(jq -r '.file // empty' <<< "$entry")
        if [ "$(jq -r '.pinned // false' <<< "$entry")" = "true" ] && [ "$old_version" != "none" ]; then
            echo "$slug: pinned at $old_version"
            continue
        fi

        channel=$(jq -r '.channel // "release"' <<< "$entry")
        local query=(--data-urlencode 'loaders=["paper","spigot","bukkit"]')
        # jq's // treats false as missing, so compare explicitly
        if [ "$(jq -r '.game_version_filter == false' <<< "$entry")" = "false" ]; then
            query+=(--data-urlencode "game_versions=[\"$minecraft_version\"]")
        fi

        versions=$(curl -fsS -G -H "User-Agent: $USER_AGENT" "${query[@]}" "$API/project/$slug/version")

        # Modrinth returns versions newest first
        latest=$(jq -c --arg channel "$channel" '
            [ .[] | select(
                .version_type == "release"
                or ($channel != "release" and .version_type == "beta")
                or ($channel == "alpha" and .version_type == "alpha")
            ) ][0]
            | if . == null then null else
                (.files | (map(select(.primary))[0] // .[0])) as $f
                | { version: .version_number, file: $f.filename, url: $f.url, sha512: $f.hashes.sha512 }
              end' <<< "$versions")

        if [ "$latest" = "null" ]; then
            echo "$slug: NO compatible $channel version for Minecraft $minecraft_version (current: $old_version)"
            FAILED=1
            continue
        fi

        new_version=$(jq -r '.version' <<< "$latest")
        if [ "$new_version" = "$old_version" ]; then
            echo "$slug: up to date ($old_version)"
            continue
        fi

        echo "$slug: $old_version -> $new_version"
        jq --argjson i "$i" --argjson latest "$latest" '.plugins[$i] += $latest' "$TMP" > "$TMP.new"
        mv "$TMP.new" "$TMP"
        # Remember the superseded JAR so sync can remove it
        [ -z "$old_file" ] || echo "$old_file" >> "$STALE"
    done
}

parse_target() {
    # Accept a bare slug or a Modrinth project URL
    if [[ "$TARGET" =~ ^https?://(www\.)?modrinth\.com/[a-z]+/([^/?#]+) ]]; then
        echo "${BASH_REMATCH[2]}"
    else
        echo "$TARGET"
    fi
}

remove_plugin() {
    local target entry file
    target=$(parse_target)

    # Match by slug, or by file name for direct-URL entries
    entry=$(jq -c --arg t "$target" '[.plugins[] | select(.slug == $t or .file == $t)][0] // empty' "$LOCK")
    [ -n "$entry" ] || { echo "$target is not in $LOCK"; exit 1; }
    file=$(jq -r '.file // empty' <<< "$entry")

    jq --arg t "$target" '.plugins |= map(select(.slug != $t and .file != $t))' "$LOCK" > "$TMP.new"
    cp "$TMP.new" "$LOCK"

    if [ -n "$file" ] && [ -f "$PLUGINS_DIR/$file" ]; then
        echo "Removing plugin JAR file: $file"
        rm "$PLUGINS_DIR/$file"
    fi
    echo "Removed $target from $LOCK (its data folder in $PLUGINS_DIR was left in place)"
}

add_plugin() {
    # Append a bare { "slug": ... } entry; resolve then fills in the rest
    local slug project title type
    slug=$(parse_target)

    project=$(curl -sf -H "User-Agent: $USER_AGENT" "$API/project/$slug") \
        || { echo "Modrinth project not found: $slug"; exit 1; }
    # Canonical slug, in case a project ID was given
    slug=$(jq -r '.slug' <<< "$project")
    title=$(jq -r '.title' <<< "$project")
    type=$(jq -r '.project_type' <<< "$project")

    case "$type" in
        plugin|mod) ;;
        *) echo "$title ($slug) is a $type, not a plugin"; exit 1 ;;
    esac

    if jq -e --arg slug "$slug" '.plugins[] | select(.slug == $slug)' "$LOCK" > /dev/null; then
        echo "$slug is already in $LOCK"
        exit 0
    fi

    echo "Adding $title ($slug)"
    jq --arg slug "$slug" '.plugins += [{ slug: $slug }]' "$LOCK" > "$TMP.new"
    cp "$TMP.new" "$LOCK"
    mv "$TMP.new" "$TMP"
    ONLY="$slug"
}

sync() {
    local file url sha512 tmp_jar jar
    mkdir -p "$PLUGINS_DIR"

    while IFS=$'\t' read -r file url sha512; do
        if [ -z "$file" ] || [ -z "$url" ] || [ -z "$sha512" ]; then
            echo "Incomplete entry in $LOCK (run ./plugins.sh update): $file $url"
            exit 1
        fi

        if [ -f "$PLUGINS_DIR/$file" ] && echo "$sha512  $PLUGINS_DIR/$file" | sha512sum -c --status -; then
            continue
        fi

        echo "Downloading plugin JAR file: $file"
        tmp_jar=$(mktemp)
        curl -fsSL -o "$tmp_jar" "$url"
        if ! echo "$sha512  $tmp_jar" | sha512sum -c --status -; then
            rm -f "$tmp_jar"
            echo "Checksum mismatch for $file"
            exit 1
        fi
        mv "$tmp_jar" "$PLUGINS_DIR/$file"
        chmod 644 "$PLUGINS_DIR/$file"
    done < <(jq -r '.plugins[] | [.file, .url, .sha512] | @tsv' "$LOCK")

    # Superseded versions would load next to the new one, so remove them
    if [ -s "$STALE" ]; then
        while read -r file; do
            if ! jq -e --arg file "$file" '.plugins[] | select(.file == $file)' "$LOCK" > /dev/null \
                && [ -f "$PLUGINS_DIR/$file" ]; then
                echo "Removing old plugin JAR file: $file"
                rm "$PLUGINS_DIR/$file"
            fi
        done < "$STALE"
    fi

    # Paper loads every JAR in the folder, so flag the ones this script doesn't know about
    for jar in "$PLUGINS_DIR"/*.jar; do
        [ -e "$jar" ] || continue
        jq -e --arg file "$(basename "$jar")" '.plugins[] | select(.file == $file)' "$LOCK" > /dev/null \
            || echo "WARNING: $jar is not in $LOCK and will still be loaded by Paper"
    done
}

TMP=$(mktemp)
STALE=$(mktemp)
BACKUP=$(mktemp)
trap 'rm -f "$TMP" "$TMP.new" "$STALE" "$BACKUP"' EXIT
cp "$LOCK" "$TMP"
cp "$LOCK" "$BACKUP"
FAILED=0

if [ "$MODE" = "remove" ]; then
    remove_plugin
    exit 0
fi

if [ "$MODE" = "add" ]; then
    add_plugin
fi

if [ "$MODE" != "sync" ]; then
    resolve
fi

if [ "$MODE" = "add" ] && [ "$FAILED" -ne 0 ]; then
    cp "$BACKUP" "$LOCK"
    echo "Not added. If it only has pre-releases or lags on game version tags, add it to $LOCK by hand"
    echo "with \"channel\" or \"game_version_filter\": false and run ./plugins.sh update"
    exit 1
fi

if [ "$MODE" != "check" ]; then
    cp "$TMP" "$LOCK.new"
    mv "$LOCK.new" "$LOCK"
    sync
fi

exit $FAILED
