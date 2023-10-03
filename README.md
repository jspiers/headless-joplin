# headless-joplin
Dockerized instance of the [Joplin](https://github.com/laurent22/joplin/) terminal client, with its web clipper service made externally acessible using [socat](https://www.cyberciti.biz/faq/linux-unix-tcp-port-forwarding/) to forward the container's external port `0.0.0.0:80` to the Joplin Clipper Server (which runs in the container bound to `127.0.0.1:41184`).
Synchronization, encryption, and other Joplin parameters may be configured by mounting a Joplin config JSON file to `/run/secrets/joplin-config.json` or creating a secret named `joplin-config.json` in a `docker-compose.yml` file.

## Basic Usage:

```
$ docker run --rm -p 3000:80 jspiers/headless-joplin:2.12.1-node-18.18.0
```
and check that the Clipper server is running from your host's command-line:
```
$ curl http://localhost:3000/ping
```
You should get a response of `JoplinClipperServer`

Or build it yourself and interact via a Bash shell instead of running the clipper server:
```
$ docker build . -t headless-joplin
$ docker run --rm -p 3000:80 -it headless-joplin bash
```

## Build Options:
### Set Node and/or Joplin versions
```
$ docker build . -t headless-joplin --build-arg NODE_VERSION=16 --build-arg JOPLIN_VERSION=2.3.2
```

## Run Options:
### Joplin Config File
Add a Joplin configuration JSON file (i.e. with the contents of a `joplin config --export` from another Joplin instance) to `./joplin-config.json` and it will be loaded via `joplin --import` in the docker container.

```
$ docker run --rm -p 3000:80 -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json headless-joplin
```

See the [official Joplin terminal documentation](https://joplinapp.org/terminal/#commands) for possible key/value pairs. Note that there are also several unofficial key/value pairs (these can be exported by adding the '-v' flag to the export command: `joplin config --export -v`). In particular, encryption of notes can be enabled via `encryption.enabled` and `encryption.masterPassword`.

Sample `joplin-config.json` for S3-based sync:
```json
{
  "sync.target": 8,
  "sync.8.url": "https://s3.us-east-1.wasabisys.com",
  "sync.8.path": "bucket",
  "sync.8.username": "S3ACCESSKEY",
  "sync.8.password": "S3SECRET",
  "sync.maxConcurrentConnections": 5,
  "sync.resourceDownloadMode": "manual",
  "sync.wipeOutFailSafe": true,
  "api.token": "mysupersecrettoken123"
}
```

## Persistent Joplin Volume
```
$ docker run --rm -p 3000:80 -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json -v joplin-data:/home/node/.config/joplin headless-joplin
```

## Interactive bash shell (instead of starting Joplin Clipper server)
```
$ docker run --rm -p 3000:80 -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json -v joplin-data:/home/node/.config/joplin -it headless-joplin bash
```

## Docker Compose
### Building the Docker Image
Just run the following in the root directory of the repo:

```
$ docker compose build
```

### Deployment Examples
See the [examples](examples) subdirectory for `docker-compose.yml` files suitable for a few scenarios.
