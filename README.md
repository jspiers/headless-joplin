# docker-joplin-cli
Dockerized [Joplin](https://github.com/laurent22/joplin/) terminal client

### Usage:
```
docker build . -t joplin-cli
docker run --rm -it joplin-cli
```

#### Optional:
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
