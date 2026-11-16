# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## What this project is

`nettest-portable` (GitHub: `richb-hanover/nettest-portable`, Docker Hub:
`richbhanover/nettest-portable`) is a Docker setup that turns a small Linux board into a network test
server you can drop onto any network. Everything is defined by a `Dockerfile` and
a `docker-compose.yml` in this directory; user-facing documentation is `README.md`.

## Requirements (from the owner)

These are the instructions this project was built from. Keep them satisfied when
making changes.

1. **Target platform:** Ubuntu 26.04 (Armbian 26.8) on arm64. The image must
   also build for amd64 and armhf.
2. **Install and start these servers:**
   - **netperf** (`netserver`)
   - **iperf** (v2) and **iperf3**
   - **Crusader server**, from https://github.com/Zoxc/crusader (prebuilt release binaries)
   - **Cutie**, from https://github.com/richb-hanover/Cutie-Network-Quality-Test
3. **About page on port 80:** a separate HTTP server that simply displays the
   contents of `ABOUT.md`. `ABOUT.md` is Markdown written by the owner and must be
   formatted to look good in a browser.
4. **mDNS:** the box advertises the name **`nettest.local`** (via an `mdns`
   service in the stack).
5. **Docker Hub:** the image is published as **`<user>/nettest-portable`**
   (`publish.sh`). The Docker Hub user name is set by `DOCKERHUB_USER` in `.env`.
6. **Documentation and all files live in this directory.** Keep `README.md` up
   to date with every change.
7. **No git checkout on the board:** `ABOUT.md` is built into the image, and a
   board needs only `docker-compose.yml`.
8. **Versioning:** the release version and date live in `ABOUT.md`
   (`_Version 0.1.0 - 14Nov2026_`); every release bumps it by 0.0.1.

## Layout

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Multi-stage build: `cutie-build` (Node, builds Cutie from GitHub), `about-build` (installs `marked`, copies `ABOUT.md`), `crusader-fetch` (downloads the binary for `TARGETARCH`), then an `ubuntu:26.04` runtime |
| `docker-compose.yml` | One shared image (`${NETTEST_IMAGE:-richbhanover/nettest-portable:latest}`), one service per server, defined via the `x-nettest` YAML anchor. The only file a board needs |
| `about/server.mjs`, `about/package.json` | Port 80 server that renders the built-in `/opt/about/ABOUT.md` with `marked` |
| `mdns/start.sh` | Generates `/etc/avahi/avahi-daemon.conf` + `_http._tcp` service files from env vars, then execs `avahi-daemon` |
| `ABOUT.md` | **Owned by the user.** Content for the About page, built into the image. Holds the release version line `_Version X.Y.Z - DMonYYYY_` (only `publish.sh` changes it). Do not otherwise rewrite it unless asked. |
| `publish.sh` | Bumps the patch version + date in `ABOUT.md` (restored if the build fails), then multi-arch (`linux/arm64,linux/amd64`) `buildx` build, pushed to `docker.io/$DOCKERHUB_USER/nettest-portable` with `latest` + `X.Y.Z` tags; `PUSH=0` = test build, no bump |
| `.env.example` | Template for `.env`: `DOCKERHUB_USER`, `NETTEST_IMAGE` (both optional on a board) |
| `.dockerignore` | Allow-list: only `ABOUT.md`, `about/package.json`, `about/server.mjs`, `mdns/start.sh` go to the build. New files copied by the Dockerfile must be added here. |
| `README.md` | User documentation (install, run, ports, configuration, firewall, troubleshooting, what was verified) |

## Services and ports

| Service | Command | Port(s) |
| --- | --- | --- |
| `netperf` | `netserver -D -p 12865` | 12865/tcp + ephemeral data ports |
| `iperf` | `iperf -s -p 5001` | 5001/tcp |
| `iperf3` | `iperf3 -s -p 5201` | 5201/tcp+udp |
| `crusader` | `crusader serve --port 35481` | 35481/tcp+udp |
| `cutie` | `node build` (in `/opt/cutie`, `HOST`/`PORT` env) | 4173/tcp + ephemeral UDP (WebRTC) |
| `about` | `node /opt/about/server.mjs` | 80/tcp |
| `mdns` | `/opt/mdns/start.sh` | 5353/udp |

## Design decisions (don't undo these without a reason)

- **Every service uses `network_mode: host`.** netperf data connections, Cutie's
  WebRTC ICE candidates (random UDP ports), and Crusader/iperf3 UDP tests need
  real host ports, NAT would distort latency results, and mDNS multicast doesn't
  cross Docker's bridge. Don't add `ports:` mappings.
- **One image, one container per server.** No supervisord. Each service has its
  own logs and restarts independently (`restart: unless-stopped`). `tini` is the
  image `ENTRYPOINT`.
- **Run unprivileged.** The image's default user is `nettest`. Only `about` and
  `mdns` start as `root`, with `cap_drop: [ALL]`, a minimal `cap_add`, and
  `no-new-privileges`:
  - `about` binds port 80, then drops to `nettest` itself (`process.setuid`).
  - `mdns` runs `avahi-daemon --no-chroot --no-rlimits`, which drops to the `avahi` user.
- **Node.js** in the runtime is copied from the official `node:24-bookworm-slim`
  build stage (`/usr/local/bin/node`), not installed from apt.
- **Cutie** is cloned at build time (`CUTIE_REF` build arg, default `main`) and
  runs as a production adapter-node build with pruned prod `node_modules`
  (includes the native `@roamhq/wrtc` module, which has a linux-arm64 prebuilt).
- **Crusader** comes from the GitHub release tarball (`CRUSADER_VERSION`, default
  `v0.3.2`); the binaries are static. The `crusader-fetch` stage uses
  `FROM --platform=$BUILDPLATFORM` so it runs natively during cross-builds:
  under QEMU, Ubuntu 26.04's `tar` fails with "Function not implemented". Asset names: `Crusader-Linux-ARM-64-bit`,
  `Crusader-Linux-ARM-32-bit`, `Crusader-Linux-X86-64-bit`.
- **Deployment needs no git checkout:** a board fetches `docker-compose.yml`
  (curl from GitHub raw) and runs `docker compose pull && docker compose up -d`.
  Don't reintroduce bind mounts of repo files.
- **About page:** `ABOUT.md` is always built into the image at
  `/opt/about/ABOUT.md` (no volume mount, no optional/override path). It is read
  and rendered once at startup; if it can't be read the server exits. Only `/`,
  `/index.html` (rendered HTML) and `/ABOUT.md` (raw) are served; everything
  else returns 404. Styling is
  inline GitHub-like CSS with light/dark support and a responsive layout; the
  page `<title>` comes from the first `# Heading`.
- **mDNS:** configured by `MDNS_NAME` (default `nettest`), `MDNS_INTERFACES`,
  `MDNS_ABOUT_PORT`, `MDNS_CUTIE_PORT`. D-Bus is disabled. Only one mDNS
  responder may run per host, so the README tells users to disable the host's
  own `avahi-daemon`.

## Commands

```bash
docker compose config -q              # validate the compose file
docker compose build                  # build $NETTEST_IMAGE (default richbhanover/nettest-portable:latest)
docker compose up -d --build          # build and start everything
docker compose up -d about mdns       # start selected services
docker compose ps
docker compose logs -f <service>
docker compose down
sh -n mdns/start.sh                   # syntax-check the mDNS script
DOCKERHUB_USER=x PUSH=0 ./publish.sh  # multi-arch test build, no push, no version bump
NO_CACHE=1 ./publish.sh               # fresh rebuild (latest Cutie + Ubuntu packages) + push
./publish.sh                          # bump version in ABOUT.md, build + push (only when asked)
```

## Testing changes

There is no test suite. Verify by building and exercising each server with the
client tools that are in the image (they share the host network):

```bash
docker exec nettest-iperf netperf -H 127.0.0.1 -l 2
docker exec nettest-iperf iperf -c 127.0.0.1 -t 2
docker exec nettest-iperf iperf3 -c 127.0.0.1 -t 2        # add -u for UDP
docker exec -w /tmp nettest-iperf crusader test 127.0.0.1 --load-duration 2
docker exec nettest-about node -e 'fetch("http://127.0.0.1/").then(r=>console.log(r.status))'
docker exec nettest-cutie node -e 'fetch("http://127.0.0.1:4173/api/stats").then(r=>r.text()).then(console.log)'
# mDNS (unicast query to the responder):
docker run --rm --network host ubuntu:26.04 sh -c 'apt-get update -qq && apt-get install -qq -y bind9-dnsutils >/dev/null && dig +short -p 5353 @127.0.0.1 nettest.local A'
```

Notes:
- Development happens on an Apple Silicon Mac with Docker Desktop (arm64). Its
  "host" network is the Docker VM, not the Mac's LAN, so multicast mDNS and
  browser-to-Cutie WebRTC can only be fully verified on the real board.
- When testing the About page with other content, don't edit `ABOUT.md` (it
  belongs to the user); use a sample file in a scratch directory and a
  temporary `docker run ... -v <file>:/opt/about/ABOUT.md:ro`.
- Bind-mounted file edits can take a moment to sync under Docker Desktop on macOS.
- After testing, `docker compose down` and remove any temporary containers.

## Conventions

- Pin versions (base images by tag, `marked` exactly, Crusader by release tag).
- Keep the README's tables (servers/ports, files, configuration, firewall) and
  its "What was verified" section in sync with the code.
- Don't commit, `git push`, or push images to Docker Hub unless the owner asks.
