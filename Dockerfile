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
        socat

# Load Joplin config using s6 oneshot
ENV JOPLIN_CONFIG_JSON=/run/secrets/joplin-config.json
RUN mkdir -p /etc/s6-overlay/s6-rc.d/joplin-config
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/joplin-config/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/joplin-config/up
importas configjson JOPLIN_CONFIG_JSON
foreground {
    pipeline -w { sed "s/^/version: /" }
    joplin version
}
joplin config --import-file "\${configjson}"
EOF

# During initial Joplin sync, set master password if env var is set
ENV JOPLIN_E2EE_MASTER_PASSWORD=""
RUN mkdir -p /etc/s6-overlay/s6-rc.d/joplin-initialsync
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/joplin-initialsync/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/joplin-initialsync/up
if {
    pipeline -w { sed "s/^/initial sync: /" }
    fdmove -c 2 1
    joplin sync
}
importas pw JOPLIN_E2EE_MASTER_PASSWORD
pipeline -w { sed "s/^/e2ee: /" }
ifelse { test -z "\${pw}" } {
    echo Encryption disabled because JOPLIN_E2EE_MASTER_PASSWORD is blank or not set
}
foreground { echo "Setting master password from JOPLIN_E2EE_MASTER_PASSWORD" }
if { joplin e2ee enable -p \${pw} }
fdmove -c 2 1
joplin e2ee decrypt
EOF

# Create joplin-sync as s6 longrun
ENV JOPLIN_SYNC_INTERVAL=5m
RUN mkdir -p /etc/s6-overlay/s6-rc.d/joplin-sync
RUN echo "longrun" > /etc/s6-overlay/s6-rc.d/joplin-sync/type
COPY <<EOF /etc/s6-overlay/s6-rc.d/joplin-sync/run
#!/command/execlineb -P
multisubstitute {
    importas pw JOPLIN_E2EE_MASTER_PASSWORD
    importas sleeptime JOPLIN_SYNC_INTERVAL
}
# loopwhilex -o 0
# foreground {
    backtick -E time { date +%T }
    foreground { echo \${time}: Next joplin sync in \${sleeptime}... }
    foreground { sleep \${sleeptime} }
    if {
        pipeline -w { sed "s/^/sync: /" }
        fdmove -c 2 1
        joplin sync
    }
    ifelse { test -z "\${pw}" } {
        echo JOPLIN_E2EE_MASTER_PASSWORD is not set
    }
    pipeline -w { sed "s/^/e2ee: /" }
    fdmove -c 2 1
    joplin e2ee decrypt
# }
# foreground { echo THIS SHOULD NOT EVER RUN }
# exit 1
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

# Activate joplin-initialsync s6 oneshot
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/joplin-initialsync \
 && mkdir -p /etc/s6-overlay/s6-rc.d/joplin-initialsync/dependencies.d/ \
 && touch /etc/s6-overlay/s6-rc.d/joplin-initialsync/dependencies.d/joplin-config

# Activate joplin-sync s6 service
RUN touch /etc/s6-overlay/s6-rc.d/user/contents.d/joplin-sync \
 && mkdir -p /etc/s6-overlay/s6-rc.d/joplin-sync/dependencies.d/ \
 && touch /etc/s6-overlay/s6-rc.d/joplin-sync/dependencies.d/joplin-initialsync

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
