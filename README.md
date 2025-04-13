# PaperMC deployment

This repo hosts files to rapidly deploy a Minecraft PaperMC Server using Docker Compose.

## Basic usage

### Quick start

1. Put the version of Minecraft you want to host inside the `.env` file.
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
- Upgrading to a newer MC version should be fine, but downgrading to an older version should
  not be attempted! It may cause a failure to start due to permanent data loss or corruption. 

If you want to use Minecraft 1.24.1, the file must be set to:
```dotenv
MINECRAFT_VERSION=1.21.4
```

#### New plugins

Add the plugin JAR file into the `plugins` directory. Restart the server with:
```shell
docker compose restart 
```