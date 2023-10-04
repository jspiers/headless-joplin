# headless-joplin

Dockerized instance of the [Joplin](https://github.com/laurent22/joplin/) terminal client, with its web clipper service made externally acessible using [socat](https://www.cyberciti.biz/faq/linux-unix-tcp-port-forwarding/) to forward the container's external port `0.0.0.0:80` to the Joplin Clipper Server (which runs in the container bound to `127.0.0.1:41184`).

Synchronization, encryption, and other Joplin parameters may be configured by mounting a Joplin config JSON file to `/run/secrets/joplin-config.json` or equivalently by creating a secret named `joplin-config.json` in a `docker-compose.yml` file.

## Basic Usage:

Try out one of the tagged images from [Docker Hub](https://hub.docker.com/r/jspiers/headless-joplin/tags):
```
$ docker run --rm -d -p 3000:80 --name my_joplin_container jspiers/headless-joplin:2.12.1-node-18.18.0
```
Then check that the Joplin Clipper server (i.e. [Data API](https://joplinapp.org/api/references/rest_api/)) is running from your host's command-line:
```
$ curl http://localhost:3000/ping
```
You should get a response of `JoplinClipperServer`.

You can also open the [Joplin terminal client](https://joplinapp.org/terminal/) running on the container to interactively view/edit notes:
```
$ docker exec -it my_joplin_container joplin
```

When done, stop the container:
```
$ docker stop my_joplin_container
```

Because we specified the `--rm` option when invoking `docker run` above, the container is automatically deleted.

## Build Options:

If you clone the repo, you can also build the Docker image yourself:
```
$ docker build . -t headless-joplin
$ docker run --rm -p 3000:80 -it headless-joplin bash
```

### Set Joplin and/or Node versions
```
$ docker build . -t headless-joplin --build-arg JOPLIN_VERSION=2.3.2 --build-arg NODE_VERSION=16
```
Suitable [Joplin versions](https://www.npmjs.com/package/joplin?activeTab=versions) are those of the `joplin` [NPM package](https://www.npmjs.com/package/joplin).

Node versions are those of the official `node` Docker images on [Docker Hub](https://hub.docker.com/_/node/tags).

## Run Options:

### Environment Variables
Set `JOPLIN_LOG_ENABLED=true` to have the contents of Joplin's log file (`log.txt`) included in Docker's output in real time.

### Joplin Config File
Add a Joplin configuration JSON file (i.e. with the contents of a `joplin config --export` from another Joplin instance) to `./joplin-config.json` and it will be loaded via `joplin --import` in the docker container.

```
$ docker run --rm -p 3000:80 -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json headless-joplin
```

See the [official Joplin terminal documentation](https://joplinapp.org/terminal/#commands) for possible key/value pairs. **Note:** there are also several unofficial key/value pairs, which can be exported/observed by adding the '-v' flag to the export command: `joplin config --export -v`. For example, the encryption master password can be set via `encryption.masterPassword`.

#### Default Configuration
This Docker container includes a hard-coded set of default configurations in the [joplin-config-defaults.json](joplin-config-defaults.json) file.

Sample `joplin-config.json` for S3-based sync:
```json
{
  "sync.target": 8,
  "sync.8.url": "https://s3.us-east-1.wasabisys.com",
  "sync.8.path": "bucket",
  "sync.8.username": "S3ACCESSKEY",
  "sync.8.password": "S3SECRET",
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
