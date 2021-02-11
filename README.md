# docker-joplin-cli
Dockerized [Joplin](https://github.com/laurent22/joplin/) terminal client

## Basic Usage:
```
docker-compose run --build --rm joplin
```

```
docker build . -t joplin-cli
docker run --rm -it joplin-cli
```

### Build Options:
#### Set Node and/or Joplin versions
```
docker build . -t joplin-cli --build-arg NODE_VERSION=15 --build-arg JOPLIN_VERSION=1.6.4
```

### Run Options:
#### Joplin Config File
Add a Joplin configuration JSON file o(i.e. with the contents of a `joplin config --export` from another Joplin instance) to `./joplin-config.json` and it will be loaded via `joplin --import-file` in the docker container.

```
docker run --rm -it -v $(pwd)/joplin-config.json:/secrets/joplin-config.json joplin-cli
```

Sample `joplin-config.json` for S3-based sync:
```
{
  "sync.target": 8,
  "sync.8.url": "https://s3.us-east-1.wasabisys.com",
  "sync.8.path": "bucket",
  "sync.8.username": "S3ACCESSKEY",
  "sync.8.password": "S3SECRET",
  "sync.interval": 300,
  "sync.maxConcurrentConnections": 5,
  "sync.resourceDownloadMode": "manual",
  "sync.wipeOutFailSafe": true,
  "api.port": 41187,
  "api.token": "abc123"
}
```

#### Persistent Joplin Volume
```
docker run --rm -it -v $(pwd)/joplin-config.json:/secrets/joplin-config.json -v joplin-data:/home/node/.config/joplin joplin-cli
```

#### Run Joplin Server
```
docker run --rm -v $(pwd)/joplin-config.json:/secrets/joplin-config.json -v joplin-data:/home/node/.config/joplin joplin-cli joplin server start
```
