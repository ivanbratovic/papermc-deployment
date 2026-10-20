# PaperMC Docker deployment

This repo hosts files to rapidly deploy a Minecraft PaperMC Server using Docker Compose.

## Basic usage

### Quick start

1. Put the version of Minecraft with the Java version you want to host inside the `.env` file.
   If you want to use Minecraft 26.3 that needs Java 25, the file must be set to:
   ```dotenv
   MINECRAFT_VERSION=26.3
   JAVA_VERSION=25
   ```
2. Verify the contents of the `server.properties` file. Make sure it works for you.
3. Create the `plugins` and `config` directories. Make sure they're in the same
    location as the Compose YAML file. You can run:
    ```shell
    mkdir ./plugins ./config
    ```
4. You can put any plugins (JAR files) compatible with PaperMC in the `plugins` directory.
5. Spin up the server with Docker Compose:
    ```shell
    docker compose up -d
    ```

### Updating the server

You can either update just to a new PaperMC build (Option 1), or update to a totally
new Minecraft version (Option 2).

#### (Option 1) Same Minecraft version, new PaperMC build

Start the build process again. The latest JAR will be downloaded during build-time.
You can use this command:

```shell
docker compose up -d --build
```

#### (Option 2) New Minecraft version

Modify the `.env` file to contain the Minecraft version you want to deploy.

**Important Notes**:
- A stable version of the PaperMC server must be available. The build will fail otherwise.
- Java version must be set correctly, or else the server won't be able to start
- Upgrading to a newer MC version should be fine, but downgrading to an older version should
  not be attempted! It may cause a failure to start due to permanent data loss or corruption.

### Plugins

Plugins are pinned in `plugins.json` (version, URL and sha512) and the JARs live in the
`plugins` directory as usual. `plugins.sh` keeps the two in sync. Requires `curl` and `jq`
on the host.

#### Add a plugin

Give `plugins.sh` the Modrinth slug or project URL. It pins the newest compatible version in
`plugins.json`, then downloads and verifies the JAR:
```shell
./plugins.sh add chunky
./plugins.sh add https://modrinth.com/plugin/chunky
docker compose restart
```

If the plugin has no compatible release, nothing is added. Plugins that only publish pre-releases
or lag on game version tags can be added to `plugins.json` by hand (see the settings below),
followed by `./plugins.sh update`.

Optional per-plugin settings:
- `"pinned": true` - never bump this plugin
- `"game_version_filter": false` - ignore the Minecraft version when resolving (useful for
  plugins that lag on game version tags, e.g. ViaVersion)
- `"channel": "beta"` (or `"alpha"`) - also allow pre-release versions

Plugins not on Modrinth can be added as a direct entry without a `slug`:
`{ "file": "X.jar", "url": "https://...", "sha512": "..." }`. The script downloads these
but never bumps them.

#### Remove a plugin

```shell
./plugins.sh remove chunky
docker compose restart
```

This drops the plugin from `plugins.json` and deletes its JAR. The plugin's data folder in
`plugins` (configs, databases) is left in place, so delete it yourself if you want it gone.

#### Update plugins

```shell
./plugins.sh check    # only report available updates
./plugins.sh update   # pin newest compatible versions, download them, remove the old JARs
git diff plugins.json # review
docker compose restart
```

On a fresh deployment, `./plugins.sh sync` downloads exactly the pinned versions.

Before upgrading Minecraft, set the new `MINECRAFT_VERSION` in `.env` and run
`./plugins.sh check` to see which plugins have no compatible version yet.

Paper loads every JAR in `plugins`, so the script warns about JARs that aren't in
`plugins.json`. Delete those, or two versions of the same plugin will conflict.
