# Build and install Joplin CLI into a first image
# Set build arguments to specify particular versions of node and Joplin
ARG NODE_VERSION=lts
ARG JOPLIN_VERSION=latest
FROM node:${NODE_VERSION}-buster-slim as builder
RUN apt-get update \
 && apt-get install --no-upgrade -y \
       git \
       python-minimal \
       build-essential \
       libsecret-1-0 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# https://github.com/nodejs/node-gyp/issues/1236#issuecomment-309447800
USER node
RUN NPM_CONFIG_PREFIX=/home/node/.joplin-bin npm --unsafe-perm -g install "joplin@${JOPLIN_VERSION}"

# Copy the built Joplin directory into a clean Debian image
FROM node:${NODE_VERSION}-buster-slim as release
RUN apt-get update \
 && apt-get install --no-upgrade -y \
       tini \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*
COPY --from=builder --chown=node:node /home/node/.joplin-bin /home/node/.joplin-bin
ENV PATH=$PATH:/home/node/.joplin-bin/bin

# Configure Joplin by importing a JSON configuration file from a mounted volume
# (updated entrypoint script performs "joplin config --import-file $JOPLIN_CONFIG_JSON")
ENV JOPLIN_CONFIG_JSON=/secrets/joplin-config.json
VOLUME /secrets
COPY --chown=node:node entrypoint.sh /entrypoint.sh
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
WORKDIR /home/node
CMD ["bash"]

# Joplin config directory can be mounted for persistence of config and database
USER node
RUN mkdir -p /home/node/.config/joplin
VOLUME /home/node/.config/joplin
