#!/usr/bin/env bash

PROJECT="$1"
MINECRAFT_VERSION="$2"

BASE_URL="https://fill.papermc.io/v3"

LATEST_BUILD=$(curl -s ${BASE_URL}/projects/${PROJECT}/versions/${MINECRAFT_VERSION}/builds | jq -r '.[0]' 2>/dev/null)

if [ -n "$LATEST_BUILD" ]; then
    JAR_NAME=$(echo "$LATEST_BUILD" | jq -r '.downloads."server:default".name')
    JAR_DOWNLOAD_URL=$(echo "$LATEST_BUILD" | jq -r '.downloads."server:default".url')
	SHA256_CHECKSUM=$(echo "$LATEST_BUILD" | jq -r '.downloads."server:default".checksums.sha256')

    echo "Downloading server JAR file: $JAR_NAME"

    # Download the latest Paper version
    curl -# -o server.jar $JAR_DOWNLOAD_URL
    echo "Download completed, verifying checksum"

    echo "${SHA256_CHECKSUM} server.jar" | sha256sum -c - || exit 1
else
    echo "No stable build for version $MINECRAFT_VERSION found :("
    exit 1
fi

