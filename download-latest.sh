#!/usr/bin/env sh

PROJECT="$1"
MINECRAFT_VERSION="$2"

LATEST_BUILD=$(curl -s https://api.papermc.io/v2/projects/${PROJECT}/versions/${MINECRAFT_VERSION}/builds | \
    jq -r '.builds | map(select(.channel == "default") | .build) | .[-1]' 2>/dev/null || echo "null")

if [ "$LATEST_BUILD" != "null" ]; then
    JAR_NAME=${PROJECT}-${MINECRAFT_VERSION}-${LATEST_BUILD}.jar
    PAPERMC_URL="https://api.papermc.io/v2/projects/${PROJECT}/versions/${MINECRAFT_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"

    echo "Downloading server JAR file for ${PROJECT} ${MINECRAFT_VERSION}, build #${LATEST_BUILD}"

    # Download the latest Paper version
    curl -# -o server.jar $PAPERMC_URL
    echo "Download completed"
else
    echo "No stable build for version $MINECRAFT_VERSION found :("
    exit 1
fi

