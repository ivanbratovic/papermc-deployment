FROM openjdk:21-slim-bullseye

ARG PROJECT=paper
ARG MINECRAFT_VERSION

# Update machine and install dependencies
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y unzip curl jq netcat-openbsd

# Working directory
RUN mkdir -p /server
WORKDIR /server
RUN mkdir backup world

# Setup server files
ADD https://api.papermc.io/v2/projects/${PROJECT}/versions/${MINECRAFT_VERSION}/ available_builds
COPY download-latest.sh .
RUN sh ./download-latest.sh $PROJECT $MINECRAFT_VERSION
RUN echo "eula=true" > eula.txt

# Entrypoint
CMD ["java", "-Xms5G", "-Xmx10G", "-jar", "server.jar"]

# Healthcheck
HEALTHCHECK CMD nc localhost 25565 -w 1