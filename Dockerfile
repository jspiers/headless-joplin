# syntax=docker/dockerfile:1

# Build and install Joplin CLI into a first image
# Set build arguments to specify particular versions of node and Joplin
ARG NODE_VERSION=lts
ARG JOPLIN_VERSION=latest
FROM node:${NODE_VERSION}-bookworm-slim as base

FROM base as builder

# Install Joplin as user "node"
USER node
RUN NPM_CONFIG_PREFIX=/home/node/.joplin-bin npm --unsafe-perm -g install "joplin@${JOPLIN_VERSION}"

# Start again from a clean base image devoid of all the build packages
FROM base as joplin

# Copy built joplin into new image and add it to the PATH
COPY --from=builder --chown=node:node /home/node/.joplin-bin /home/node/.joplin-bin
ENV PATH=$PATH:/home/node/.joplin-bin/bin

# Joplin config directory can be mounted for persistence of config and database
RUN mkdir -p /home/node/.config/joplin && chown node:node /home/node/.config/joplin
VOLUME /home/node/.config/joplin

FROM joplin as s6

# Remove any third-party apt sources to avoid issues with expiring keys
RUN rm -f /etc/apt/sources.list.d/*.list

# For apt caching as per https://docs.docker.com/engine/reference/builder/#run---mounttypecache
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
ARG S6_OVERLAY_VERSION=3.1.5.0
RUN curl -sLO https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
 && tar -C / -Jxpf s6-overlay-noarch.tar.xz \
 && rm s6-overlay-noarch.tar.xz
RUN curl -sLO https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz \
 && tar -C / -Jxpf s6-overlay-x86_64.tar.xz \
 && rm s6-overlay-x86_64.tar.xz
ENV S6_KEEP_ENV=1
ENTRYPOINT ["/init"]

FROM s6 as release

# Install some utilities for the release image
# trunk-ignore(hadolint/DL3008): allow unspecified apt package versions
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get --no-install-recommends install -y \
        socat \
        jq

# Create volume for default Joplin sync target via "local" filesystem path
VOLUME [ "/sync" ]
RUN mkdir -p /sync && chown -R node:node /sync

# Load Joplin config using s6 oneshot
ARG JOPLIN_CONFIG_DEFAULTS_JSON=/home/node/joplin-config-defaults.json
ENV JOPLIN_CONFIG_JSON=/run/secrets/joplin-config.json
ARG JOPLIN_CONFIG_REQUIRED_JSON=/home/node/joplin-config-required.json
COPY --chown=node:node joplin-config-defaults.json ${JOPLIN_CONFIG_DEFAULTS_JSON}
COPY --chown=node:node joplin-config-required.json ${JOPLIN_CONFIG_REQUIRED_JSON}
RUN mkdir -p /etc/s6-overlay/s6-rc.d/joplin-config
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/joplin-config/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/joplin-config/up
foreground {
    pipeline -w { sed "s/^/version: /" }
    joplin version
}
multisubstitute {
    define defaults ${JOPLIN_CONFIG_DEFAULTS_JSON}
    importas config JOPLIN_CONFIG_JSON
    define required ${JOPLIN_CONFIG_REQUIRED_JSON}
}
# Merge JSON files by order of precedence and feed result to "joplin config --import"
# (see https://stackoverflow.com/a/71416016/5905029 for jq expression)
pipeline { jq "reduce inputs as \$i (.; . * \$i)" \${defaults} \${config} \${required} }
joplin config --import
EOF

# Create joplin-sync as s6 longrun
RUN mkdir -p /etc/s6-overlay/s6-rc.d/joplin-sync
RUN echo "longrun" > /etc/s6-overlay/s6-rc.d/joplin-sync/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/joplin-sync/run
#!/command/execlineb -P
multisubstitute {
    define defaults ${JOPLIN_CONFIG_DEFAULTS_JSON}
    importas config JOPLIN_CONFIG_JSON
}
backtick -E sleeptime {
    # Extract sync interval from JSON config files
    # (see https://stackoverflow.com/a/71416016/5905029 for jq expression)
    jq ". * input | .[\\"sync.interval\\"]" \${defaults} \${config}
}
backtick -E encryption { joplin config encryption.enabled }
# TODO loop the remainder instead of dying and relying on s6 service restart
if {
    pipeline -w { sed "s/^/sync: /" }
    fdmove -c 2 1
    joplin sync
}
foreground {
    pipeline -w { sed "s/^/e2ee: /" }
    ifelse { test \${encryption} = "encryption.enabled = true" } {
        fdmove -c 2 1
        joplin e2ee decrypt
    }
    echo Disabled
}
backtick -E time { date +%T }
foreground { echo \${time}: Next sync in \${sleeptime}s... }
sleep \${sleeptime}
EOF

# Run socat to expose joplin clipper api bound to localhost as s6 service
# Forward external port 80 to Joplin server on 127.0.0.1:41184
# We need socat to allow external (0.0.0.0) access to hardcoded localhost port binding:
# https://github.com/laurent22/joplin/blob/d22abe69b649f5909e85a9b72400978980f1f396/packages/lib/ClipperServer.ts#L231
RUN mkdir -p /etc/s6-overlay/s6-rc.d/socat
RUN echo "longrun" > /etc/s6-overlay/s6-rc.d/socat/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/socat/run
#!/command/execlineb -P
pipeline -w { sed "s/^/socat: /" }
foreground { echo "forwarding TCP port 0.0.0.0:80 => 127.0.0.1:41184" }
fdmove -c 2 1
socat -d -ls TCP-LISTEN:80,fork TCP:127.0.0.1:41184
EOF

# Expose socat external port being forwarded to Joplin clipper server
EXPOSE 80/tcp

# Activate joplin-config s6 oneshot
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/joplin-config \
 && mkdir -p /etc/s6-overlay/s6-rc.d/joplin-config/dependencies.d/ \
 && touch /etc/s6-overlay/s6-rc.d/joplin-config/dependencies.d/base

# Activate joplin-sync s6 service
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/joplin-sync \
 && mkdir -p /etc/s6-overlay/s6-rc.d/joplin-sync/dependencies.d/ \
 && touch /etc/s6-overlay/s6-rc.d/joplin-sync/dependencies.d/joplin-config

# Activate socat s6 service
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/socat \
 && mkdir -p /etc/s6-overlay/s6-rc.d/socat/dependencies.d/ \
 && touch /etc/s6-overlay/s6-rc.d/socat/dependencies.d/base

# Increase the timeout (in milliseconds) waiting for s6 services to run/start (0 = infinity)
# (see https://github.com/just-containers/s6-overlay/tree/v3.1.5.0#customizing-s6-overlay-behaviour)
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

WORKDIR /home/node
USER node
CMD ["joplin", "server", "start"]

# Test health of Joplin Clipper server with periodic GET /ping
HEALTHCHECK --interval=30s --retries=1 --timeout=5s --start-interval=5s --start-period=30s \
     CMD curl -s http://localhost/ping | jq -R -e '. == "JoplinClipperServer"'
