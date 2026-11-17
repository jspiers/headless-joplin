# Encrypted config with sops

An opt-in example: the Joplin config is encrypted in the repository and reaches
the container through the environment, so no plaintext config exists on the
machine running `docker compose` **or** on the Docker daemon's host.

This is a variation on [`examples/s3`](../s3), whose `secrets:` stanza works by
bind-mounting a file — which assumes the daemon is local. When the daemon is
remote (`docker context` over SSH), a file decrypted on your machine has a path
the daemon cannot see. Environment variables are sent in the container-create
request, so they survive the hop.

## How it fits together

- `secrets/joplin-config.sops.json` — the config, encrypted with [sops] to the
  user's age key plus both recovery masters.
- `.envrc` — [direnv] decrypts it into the shell and exports
  `JOPLIN_CONFIG_JSON_B64`; the plaintext only ever lives in the shell's
  environment.
- The image resolves that variable into `/dev/shm/joplin-config.json` (tmpfs)
  and never writes it to the container's writable layer. Only
  `JOPLIN_CONFIG_JSON_B64` is used here; `JOPLIN_CONFIG_JSON_FILE` is the
  alternative for callers that have a file inside the container, and the image
  rejects a container that sets both.

## Usage

Build the image once from the repository root, using the versions in `.env`:

```bash
cd ../.. && docker compose build
```

Then, in this directory:

```bash
direnv allow                   # once per checkout
docker compose up -d
curl -s localhost:3000/ping    # JoplinClipperServer
```

Edit the config with:

```bash
sops secrets/joplin-config.sops.json
```

Project files are addressed to the user age key, so no master is needed. A
`sync.interval` of `0` (the current value) disables periodic sync; set it to a
positive number of seconds to have the container sync on its own.

## Trade-offs

The variable is visible to `docker inspect` and to `/proc/1/environ` inside the
container, and Docker persists a container's environment in its metadata on the
daemon's host. It keeps the plaintext out of the image, the repository and any
mounted file, but on a **local** daemon a `secrets:`-mounted file (as in
[`examples/s3`](../s3)) is the tighter option.

[sops]: https://getsops.io/
[direnv]: https://direnv.net/
