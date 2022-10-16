# Build and install Joplin CLI into a first image
# Set build arguments to specify particular versions of node and Joplin
ARG NODE_VERSION=lts-buster-slim
ARG JOPLIN_VERSION=2.9.1
FROM node:${NODE_VERSION} as base
FROM base as builder
# Install build packages necessary to compile Joplin dependencies
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-upgrade -y \
      git \
      python-minimal \
      build-essential \
      libsecret-1-0 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Install Joplin as user "node"
USER node
RUN NPM_CONFIG_PREFIX=/home/node/.joplin-bin npm --unsafe-perm -g install "joplin@${JOPLIN_VERSION}"

# Start again from a clean Debian image devoid of all the build packages
FROM base as release

# Copy built joplin into new image and add it to the PATH
COPY --from=builder --chown=node:node /home/node/.joplin-bin /home/node/.joplin-bin
ENV PATH=$PATH:/home/node/.joplin-bin/bin

# Install some utilities for the release image
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-upgrade -y \
      tini \
      jq \
      gosu \
      cron \
      socat \
      logrotate \
      curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Configure Joplin by importing a JSON configuration file from a mounted volume
# (updated entrypoint script performs "joplin config --import-file $JOPLIN_CONFIG_JSON")
ENV JOPLIN_CONFIG_JSON=/secrets/joplin-config.json
VOLUME /secrets

# Joplin config directory can be mounted for persistence of config and database
RUN mkdir -p /home/node/.config/joplin && chown node:node /home/node/.config/joplin
VOLUME /home/node/.config/joplin

# Set up entrypoint and working environment
WORKDIR /home/node
COPY --chown=node:node entrypoint.sh /entrypoint.sh
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["joplin", "server", "start"]

# Expose socat external port, forwarded to Joplin server (see entrypoint.sh script)
EXPOSE 80/tcp

# Test health of Joplin Clipper server with periodic GET /ping
HEALTHCHECK --interval=30s --retries=1 --timeout=5s \
      CMD curl -s http://localhost/ping | jq -R -e '. == "JoplinClipperServer"'
