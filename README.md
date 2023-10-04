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

## Persistent Joplin Data
To persist Joplin data between runs of the Docker container, mount a volume at `/home/node/.config/joplin`:
```
$ docker run --rm -d -p 3000:80 --name my_joplin_container -v joplin-data:/home/node/.config/joplin jspiers/headless-joplin:2.12.1-node-18.18.0
```

## Configuration:

### Environment Variables
Set `JOPLIN_LOG_ENABLED=true` to have the contents of Joplin's log file (`log.txt`) included in Docker's output in real time.

### Joplin Config File

The Joplin terminal client includes commands for importing and exporting its settings in JSON format:
```
$ joplin config --export > json-config.json
```
And then in another joplin instance:
```
$ joplin config --import-file json-config.json
```

See the [official Joplin terminal documentation](https://joplinapp.org/terminal/#commands) for supported JSON key/value pairs. **Note:** there are also several unofficial configuration keys, which can be exported/observed by adding the '-v' flag to the export command: `joplin config --export -v`. For example, the encryption master password can be set via `encryption.masterPassword`.

### How `headless-joplin` Configures Joplin
`headless-joplin` leverages the Joplin terminal client's JSON configuration functionality to configure Joplin via three files:
1. [default settings](joplin-config-defaults.json) suitable for most envisioned scenarios;
2. an optional JSON configuration file which can either be provided as a Docker secret with the name `json-config.json`, or equivalently, by mounting a JSON file at a location specified via the `JOPLIN_CONFIG_JSON` environment variable, which defaults to `/run/secrets/joplin-config.json`; and
3. [required settings](joplin-config-required.json) expected by `headless-joplin` for its correct operation[^1].

[^1]: Special note regarding `sync.interval`: When running in server mode, the Joplin terminal client does not (as of Joplin version 2.12.1) perform any synchronization of its own, even if the `sync.interval` is set to a non-zero value. To account for this, the `headless-joplin` container is designed to read the `sync.interval` value from either the defaults or the user-provided JSON config file, and periodically invoke the `joplin sync` command as a background process.

```
$ docker run --rm -d -p 3000:80 --name my_joplin_container -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json jspiers/headless-joplin:2.12.1-node-18.18.0
```

In particular, the `api.token` should be specified to override the default value for the sake of [security](#security-considerations).

#### Configuration Examples

Sample `joplin-config.json` for various scenarios are provided in the [examples](examples) directory. 


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

## Security Considerations
- HTTP not HTTPS
- should only use docker internal network
- else reverse-proxy with NGINX or traefik

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
