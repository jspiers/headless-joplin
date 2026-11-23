# syntax=docker/dockerfile:1
# The above line is needed for now to allow HEALTHCHECK --start-interval to be parsed
# https://github.com/docker/cli/issues/4486#issuecomment-1671620453

# Build and install Joplin CLI into a first image
# Set build arguments to specify particular versions of node and Joplin
# NOTE: Joplin CLI >= 3.0 is required for encryption method 8 (SJCL4) support
# which is used by Joplin Desktop >= 2.14 for E2EE
ARG NODE_VERSION=20
ARG JOPLIN_VERSION=latest
FROM node:${NODE_VERSION}-bookworm-slim as base

FROM base as builder
ARG JOPLIN_VERSION

# Install Joplin as user "node"
USER node
ENV NODE_ENV=production
ENV NPM_CONFIG_PREFIX=/home/node/.joplin-bin
RUN npm -g install "joplin@${JOPLIN_VERSION?}"

# Start again from a clean base image devoid of all the build packages
FROM base as joplin

# Copy built joplin into new image and add it to the PATH
COPY --from=builder --chown=node:node /home/node/.joplin-bin /home/node/.joplin-bin
ENV PATH=$PATH:/home/node/.joplin-bin/bin

# Joplin config directory can be mounted for persistence of config and database
RUN mkdir -p /home/node/.config/joplin && chown node:node /home/node/.config/joplin
VOLUME /home/node/.config/joplin

# Install s6-overlay to enable multiple services in same docker container
# https://github.com/just-containers/s6-overlay
FROM joplin as s6

# Remove any third-party apt sources to avoid issues with expiring keys
RUN rm -f /etc/apt/sources.list.d/*.list

# For apt caching as per https://docs.docker.com/engine/reference/builder/#example-cache-apt-packages
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install curl
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get --no-install-recommends install -y \
        curl \
        ca-certificates

# Add s6-overlay to run joplin server with proper process 1 / init supervision
# https://github.com/just-containers/s6-overlay
# https://www.troubleshooters.com/linux/execline.htm
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get --no-install-recommends install -y \
        xz-utils

# Check https://github.com/just-containers/s6-overlay/releases/ to find s6-overlay versions
ARG S6_OVERLAY_VERSION=3.1.5.0
RUN curl -sLO https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
 && tar -C / -Jxpf s6-overlay-noarch.tar.xz \
 && rm s6-overlay-noarch.tar.xz
RUN curl -sLO https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz \
 && tar -C / -Jxpf s6-overlay-x86_64.tar.xz \
 && rm s6-overlay-x86_64.tar.xz

ENTRYPOINT ["/init"]

FROM s6 as release
LABEL org.opencontainers.image.authors="jeff@cusk.io"

# Install some utilities for the release image
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get --no-install-recommends install -y \
        socat \
        jq \
        vim-tiny

# Set s6-overlay options (see https://github.com/just-containers/s6-overlay/tree/v3.1.5.0#customizing-s6-overlay-behaviour)
# Make environment variables visible to s6 scripts
ENV S6_KEEP_ENV=1
# Increase the timeout (in milliseconds) waiting for s6 services to run/start (0 = infinity)
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

# Copy s6-rc files
COPY s6-rc.d /etc/s6-overlay/s6-rc.d

# Resolve the Joplin JSON config to one path that the s6 services read, from
# either inline base64 content or an explicit file. Inline content is what makes
# config possible when the Docker daemon is remote: bind mounts are resolved on
# the daemon's host, whereas environment variables travel with the
# container-create request. The destination is defined once, in
# JOPLIN_CONFIG_JSON_RESOLVED below.
COPY <<'EOF' /usr/local/bin/joplin-config-resolve
#!/bin/sh
# Supply the config in exactly one of two ways:
#
#   JOPLIN_CONFIG_JSON_B64   base64-encoded JSON content
#   JOPLIN_CONFIG_JSON_FILE  path to a JSON file
#
# With neither set, the image's own /run/secrets/joplin-config.json is used.
# JOPLIN_CONFIG_JSON is accepted as a deprecated alias for JOPLIN_CONFIG_JSON_FILE.
set -eu

config_path="${JOPLIN_CONFIG_JSON_RESOLVED:?JOPLIN_CONFIG_JSON_RESOLVED is not set}"
content="${JOPLIN_CONFIG_JSON_B64:-}"
file="${JOPLIN_CONFIG_JSON_FILE:-}"

# JOPLIN_CONFIG_JSON is the pre-2.13 name for JOPLIN_CONFIG_JSON_FILE.
if [ -z "$file" ] && [ -n "${JOPLIN_CONFIG_JSON:-}" ]; then
    file="$JOPLIN_CONFIG_JSON"
    echo "joplin config: JOPLIN_CONFIG_JSON is deprecated, use JOPLIN_CONFIG_JSON_FILE" >&2
fi

if [ -n "$content" ] && [ -n "$file" ]; then
    echo "joplin config: set only one of JOPLIN_CONFIG_JSON_B64 or JOPLIN_CONFIG_JSON_FILE" >&2
    exit 1
fi

umask 077
rm -f "$config_path"

if [ -n "$content" ]; then
    printf '%s' "$content" | base64 -d > "$config_path"
    jq -e . "$config_path" > /dev/null
    echo "joplin config: decoded JOPLIN_CONFIG_JSON_B64" >&2
elif [ -n "$file" ]; then
    if [ ! -r "$file" ]; then
        echo "joplin config: JOPLIN_CONFIG_JSON_FILE=$file is not readable" >&2
        exit 1
    fi
    jq -e . "$file" > /dev/null
    ln -sf "$file" "$config_path"
    echo "joplin config: using JOPLIN_CONFIG_JSON_FILE=$file" >&2
else
    ln -sf /run/secrets/joplin-config.json "$config_path"
fi
EOF
RUN chmod 0755 /usr/local/bin/joplin-config-resolve

# This variable is used to enable/disable the joplin-log service (see ./s6-rc.d/joplin-log/run)
ENV JOPLIN_LOG_ENABLED="false"

# Create volume for default Joplin sync target via "local" filesystem path
VOLUME [ "/sync" ]
RUN mkdir -p /sync && chown -R node:node /sync

# Run as user "node"
WORKDIR /home/node
USER node

# Set default Joplin JSON config, imported by joplin-config s6 script (see ./s6-rc.d/joplin-config/up)
ENV JOPLIN_CONFIG_DEFAULTS_JSON=/home/node/joplin-config-defaults.json
COPY <<EOF ./joplin-config-defaults.json
{
    "api.token": "mytoken",
    "editor": "vi",
    "sync.interval": 0,
    "sync.maxConcurrentConnections": 5,
    "sync.resourceDownloadMode": "manual",
    "sync.wipeOutFailSafe": true
}
EOF

# Optional Joplin JSON config, in exactly one of these forms (see
# joplin-config-resolve). Empty means unset. The file below is the default when
# neither variable is set; mount over it to supply a config the classic way.
ENV JOPLIN_CONFIG_JSON_FILE=""
ENV JOPLIN_CONFIG_JSON_B64=""

# Where joplin-config-resolve puts the config and where the s6 services read it
# from. Internal: callers supply one of the two variables above, not this path.
ENV JOPLIN_CONFIG_JSON_RESOLVED=/dev/shm/joplin-config.json
COPY <<EOF /run/secrets/joplin-config.json
{}
EOF

# Set required Joplin JSON config overrides
ENV JOPLIN_CONFIG_REQUIRED_JSON=/home/node/joplin-config-required.json
COPY <<EOF ./joplin-config-required.json
{
    "api.port": 41184,
    "sync.interval": 0
}
EOF

# Fix tty issues in vim with "set nocompatible"
COPY <<EOF ./.vimrc
set nocompatible
EOF

# Run joplin server as daemon
CMD ["joplin", "server", "start"]

# Expose socat external port being forwarded to Joplin clipper server
EXPOSE 80/tcp

# Test health of Joplin Clipper server with periodic GET /ping
HEALTHCHECK --interval=30s --retries=1 --timeout=5s --start-interval=5s --start-period=30s \
     CMD curl -s http://localhost/ping | jq -R -e '. == "JoplinClipperServer"'
