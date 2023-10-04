# headless-joplin

A Docker which runs the [Joplin terminal client] as a daemon with its web clipper service exposed on port 80.[^1]

[^1]: Because the [Joplin terminal client] Clipper Server is [hard-coded](https://github.com/laurent22/joplin/blob/3a8aea1aa43d16d863aa0ecd6603570a429c625a/packages/lib/ClipperServer.js#L214) to bind to localhost `127.0.0.1`, the `headless-joplin` container includes a background [socat] service which redirects to that localhost port from the container's external port `0.0.0.0:80`

Synchronization, encryption, and other Joplin parameters may be configured by mounting a [JSON config file] to `/run/secrets/joplin-config.json` or equivalently by creating a secret named `joplin-config.json` in a `docker-compose.yml` file.

## Basic Usage:

Try out one of the tagged images from the [container registry]:
```
docker run --rm -d -p 3000:80 --name my_joplin_container jspiers/headless-joplin:2.12.1-node-18.18.0
```
Then check that the Joplin Clipper server (*i.e.* [Data API]) is running from your host's command-line:
```
curl http://localhost:3000/ping
```
You should get a response of `JoplinClipperServer`.

You can also open the [Joplin terminal client] running on the container to interactively view/edit notes:
```
docker exec -it my_joplin_container joplin
```

When done, stop the container:
```
docker stop my_joplin_container
```

Because we specified the `--rm` option when invoking `docker run` above, the container is automatically deleted.

## Persistent Joplin Data
To persist Joplin data between runs of the Docker container, mount a volume at `/home/node/.config/joplin`:
```
docker run --rm -d -p 3000:80 --name my_joplin_container -v joplin-data:/home/node/.config/joplin jspiers/headless-joplin:2.12.1-node-18.18.0
```

## Configuration:

### Environment Variables
Set `JOPLIN_LOG_ENABLED=true` to tell the container to display the contents of Joplin's log file (`log.txt`) in the Docker logs in real time.

### Joplin JSON Config File

The [Joplin terminal client] includes commands for importing and exporting its settings in JSON format:
```
joplin config --export > json-config.json
```
And then in another joplin instance:
```
joplin config --import-file json-config.json
```

See the [official Joplin terminal documentation](https://joplinapp.org/terminal/#commands) for supported JSON key/value pairs. **Note:** there are also several unofficial configuration keys, which can be exported/observed by adding the '-v' flag to the export command: `joplin config --export -v`. For example, the encryption master password can be set via `encryption.masterPassword`.

### How `headless-joplin` Configures Joplin
`headless-joplin` leverages the Joplin terminal client's JSON configuration functionality to configure Joplin via three files:
1. [default settings](joplin-config-defaults.json) suitable for most envisioned scenarios;
2. an optional JSON configuration file which can either be provided as a Docker secret with the name `json-config.json`, or equivalently, by mounting a JSON file at a location specified via the `JOPLIN_CONFIG_JSON` environment variable, which defaults to `/run/secrets/joplin-config.json`; and
3. [required settings](joplin-config-required.json) expected by `headless-joplin` for its correct operation.[^2]

For example, to load a `joplin-config.json` file from your current directory:
[^2]: Special note regarding `sync.interval`: When running in server mode, the Joplin terminal client does not (as of Joplin version 2.12.1) perform any synchronization of its own, even if the `sync.interval` is set to a non-zero value. To account for this, the `headless-joplin` container is designed to read the `sync.interval` value from either the defaults or the user-provided JSON config file, and periodically invoke the `joplin sync` command as a background process.

```
docker run --rm -d -p 3000:80 --name my_joplin_container -v ${PWD}/joplin-config.json:/run/secrets/joplin-config.json jspiers/headless-joplin:2.12.1-node-18.18.0
```

In particular, consider specifying `api.token` override the default value for the sake of [security](#security-considerations).

## Docker Compose
For most scenarios, it is more convenient to configure a `headless-joplin` container via a `docker-compose.yml` file.

### Examples
See the [examples] subdirectory for `docker-compose.yml` files suitable for a few scenarios.

## Build Options:

If you clone the repo, you can also build the Docker image yourself:
```
docker build . -t headless-joplin
docker run --rm -p 3000:80 -it headless-joplin bash
```

### Set Joplin and/or Node versions
```
docker build . -t headless-joplin --build-arg JOPLIN_VERSION=2.3.2 --build-arg NODE_VERSION=16
```
> Joplin version should be set to one of the official *[joplin](https://www.npmjs.com/package/joplin?activeTab=versions)* NPM package versions.

> Node version should be one of the official *[node](https://hub.docker.com/_/node/tags)* Docker image tags.

### Building with Docker Compose
Just run the following in the root directory of the repo:

```
docker compose build
```

## Security Considerations
### Insecure HTTP
Communication with the `headless-joplin` [Data API] on its exposed port 80 is via insecure HTTP. As such, care should be taken not to expose this port to public networks. The intended usage of `headless-joplin` is to communicate with other containers via an internal network (*e.g.* declared with `internal: true` in a `docker-compose.yml`).

For scenarios where the `headless-joplin` [Data API] is to be accessed via a public network, a reverse-proxy sidecar container (*i.e.* [nginx], [traefik], or [Caddy]) could be used to secure the connection.

### API Token
The default configuration sets the `api.token` to a value of `mytoken`. This should be set to a secret value provided to the container via a [JSON config file].

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[Joplin]: https://github.com/laurent22/joplin/
[Joplin terminal client]: https://joplinapp.org/terminal/
[socat]: https://linuxcommandlibrary.com/man/socat#tldr
[container registry]: https://hub.docker.com/r/jspiers/headless-joplin/
[Data API]: https://joplinapp.org/api/references/rest_api/
[JSON config file]: #joplin-json-config-file
[examples]: examples
[nginx]: https://domysee.com/blogposts/reverse-proxy-nginx-docker-compose
[traefik]: https://doc.traefik.io/traefik/user-guides/docker-compose/basic-example/
[Caddy]: https://github.com/lucaslorentz/caddy-docker-proxy
