# Build and install Joplin CLI into a first image
# Set build arguments to specify particular versions of node and Joplin
ARG NODE_VERSION=lts
ARG JOPLIN_VERSION=1.6.4
FROM node:${NODE_VERSION}-buster-slim as base
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
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --no-upgrade -y \
       tini \
       jq \
       gosu \
       cron \
       socat \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Configure Joplin by importing a JSON configuration file from a mounted volume
# (updated entrypoint script performs "joplin config --import-file $JOPLIN_CONFIG_JSON")
COPY --from=builder --chown=node:node /home/node/.joplin-bin /home/node/.joplin-bin
ENV PATH=$PATH:/home/node/.joplin-bin/bin
ENV JOPLIN_CONFIG_JSON=/secrets/joplin-config.json
VOLUME /secrets
COPY --chown=node:node entrypoint.sh /entrypoint.sh
WORKDIR /home/node
ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
CMD ["joplin", "server", "start"]

# Set up cron job for periodic "joplin sync"
COPY joplin-sync.cron /etc/cron.d/joplin-sync

# Expose external port, forwarded to Joplin server using socat (see entrypoint.sh script)
EXPOSE 80/tcp

# Joplin config directory can be mounted for persistence of config and database
RUN mkdir -p /home/node/.config/joplin && chown node:node /home/node/.config/joplin
VOLUME /home/node/.config/joplin
