# nettest-portable: a network test server in Docker

This Docker setup turns a small Linux board (Armbian 26.8 / Ubuntu 26.04, arm64)
into a network test server. You can put the box anywhere on a network and test
against it. It runs:

| Server | Version | Port(s) | What it's for |
| --- | --- | --- | --- |
| **netperf** (`netserver`) | 2.7.1 | 12865/tcp control, plus ephemeral data ports | Throughput and request/response tests |
| **iperf** (v2) | 2.2.1 | 5001/tcp | Throughput tests |
| **iperf3** | 3.20 | 5201/tcp + udp | Throughput, UDP loss and jitter |
| **Crusader** server | 0.3.2 | 35481/tcp + udp | Throughput under load plus latency ("bufferbloat") |
| **Cutie** | from `main` | 4173/tcp (HTTP), ephemeral UDP (WebRTC) | Browser-based MOS, latency, jitter and packet loss |
| **About page** | — | 80/tcp | Shows `ABOUT.md` as a formatted web page |
| **mDNS** (avahi-daemon) | 0.8 | 5353/udp | Advertises `nettest.local` and the web pages via Bonjour |

All seven run from a single image, **`nettest-portable`**, each in its own container.
You can build the image on the board or pull it from Docker Hub
(`<user>/nettest-portable`).
That way each server has its own logs and restarts independently.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Multi-stage build: builds Cutie, downloads Crusader, assembles an Ubuntu 26.04 runtime |
| `docker-compose.yml` | One service per server, all on host networking, `restart: unless-stopped` |
| `about/server.mjs`, `about/package.json` | The port 80 server that renders `ABOUT.md` |
| `mdns/start.sh` | Writes the Avahi config from environment variables and starts `avahi-daemon` |
| `ABOUT.md` | *(you create this)* The content shown on port 80 |
| `publish.sh` | Builds the image for arm64 + amd64 and pushes it to Docker Hub |
| `.env.example` | Template for `.env` (`DOCKERHUB_USER`, `NETTEST_IMAGE`) |
| `.dockerignore` | Sends only `about/` and `mdns/` to the build (everything else is fetched from GitHub/apt) |

## The About page (port 80)

The `about` service serves `ABOUT.md` (from this directory) at `http://BOX/`.
Use it to describe the box: what it is, who owns it, and how to run the tests.

- Write `ABOUT.md` in normal GitHub-flavored Markdown: headings, tables,
  code blocks, block quotes, task lists, links and images (by absolute URL).
- The page uses clean, GitHub-like styling. It follows the browser's
  light/dark preference and fits phone screens.
- The page title comes from the file's first `# Heading`.
- The file is read on every request, so edits appear on the next browser
  reload, with no restart or rebuild.
- `http://BOX/ABOUT.md` returns the raw Markdown.
- If `ABOUT.md` doesn't exist yet, the page says so (HTTP 503) instead of failing.

This directory is mounted read-only into the container at `/srv/about`. It's
mounted as a directory rather than as the single file so that editors that
save by replacing the file still work. Only `ABOUT.md` is ever served; every
other path returns 404.

Port 80 is privileged. The container starts as root with every capability
dropped except binding low ports and switching user, and it switches to the
unprivileged `nettest` user as soon as the port is open.

## mDNS: `nettest.local`

The `mdns` service runs `avahi-daemon`, so the box answers to **`nettest.local`**
wherever it's plugged in, even when DHCP gives it a different address. It also
advertises two Bonjour/DNS-SD `_http._tcp` services: *"Network test box on
nettest"* (the About page, port 80) and *"Cutie on nettest"* (port 4173). These
show up in Bonjour browsers and `avahi-browse -a`.

**Only one mDNS responder may run on a host.** Armbian often runs its own
`avahi-daemon`, which would advertise the board's real hostname and fight over
UDP port 5353. Check for it and turn it off before starting the stack:

```bash
systemctl status avahi-daemon
sudo systemctl disable --now avahi-daemon.service avahi-daemon.socket
```

(If you'd rather keep the host's Avahi, skip the container (`docker compose up -d`
followed by `docker compose stop mdns`, or delete the `mdns` service) and instead
rename the board: `sudo hostnamectl set-hostname nettest`.)

Settings, under the `mdns` service's `environment:` in `docker-compose.yml`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `MDNS_NAME` | `nettest` | Name to advertise (`.local` is added) |
| `MDNS_INTERFACES` | *(all)* | Comma-separated list, e.g. `eth0` or `eth0,wlan0` |
| `MDNS_ABOUT_PORT` | `80` | Port advertised for the About page; empty = don't advertise |
| `MDNS_CUTIE_PORT` | `4173` | Port advertised for Cutie; empty = don't advertise |

Avahi answers each query with the address of the interface the query came in
on. Docker's internal `docker0` bridge is therefore harmless, but if the board
has several network ports, `MDNS_INTERFACES` limits which networks see the name.
The container starts as root with a minimal set of capabilities, and
`avahi-daemon` switches to its own `avahi` user right after startup.

Clients: macOS, iOS and Windows 10/11 resolve `.local` names out of the box.
Linux needs `libnss-mdns` (installed by default on most desktops).
Check from a client with `ping nettest.local`, or
`dns-sd -G v4 nettest.local` on a Mac, or `avahi-resolve -n nettest.local` on Linux.

## Why host networking?

Every service uses `network_mode: host`. Publishing a fixed list of ports
(`-p 5201:5201` and so on) would break several of the tests:

- **mDNS** is multicast, which doesn't cross Docker's bridge network.
- **netperf** opens a separate data connection on a random port for each test.
- **Cutie** uses WebRTC. The server's ICE candidates are random UDP ports on
  the host's own IP address, and the browser has to reach them directly.
- **Crusader** and **iperf3 UDP** measure latency and loss. NAT through
  Docker's bridge would add latency and distort the results.

With host networking the servers act like they were installed directly on the
board. Docker's own port mapping isn't used at all.

## 1. Install Docker on Armbian 26.8 / Ubuntu 26.04

Use either Ubuntu's packages:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 docker-buildx
sudo usermod -aG docker $USER      # log out and back in afterwards
```

or Docker's upstream packages:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```

Check it with `docker compose version`.

## 2. Start it

Copy this directory to the board. Then either pull the published image or
build it locally.

**Option A: pull from Docker Hub** (fast, no build on the board):

```bash
cd nettest-portable
cp .env.example .env      # set NETTEST_IMAGE=<user>/nettest-portable:latest
docker compose pull
docker compose up -d
```

On the board you only need `docker-compose.yml`, `.env` and your `ABOUT.md`
(the About page reads it from this directory).

**Option B: build on the board:**

```bash
cd nettest-portable
docker compose up -d --build
```

The first build takes a while on a small ARM board (Cutie's `npm ci` and
`npm run build` take the most time). Later builds are cached. Without `.env`,
the locally built image is named `nettest-portable:latest`.

Because of `restart: unless-stopped`, the containers come back up after a
reboot as long as the Docker service is enabled (`sudo systemctl enable docker`,
which is the default).

Check that everything is up:

```bash
docker compose ps
docker compose logs -f            # all servers
docker compose logs -f cutie      # just one
```

## 3. Use it

Replace `BOX` with `nettest.local`, or with the board's IP address.

```bash
# netperf
netperf -H BOX -t TCP_STREAM -l 10
netperf -H BOX -t TCP_RR -l 10

# iperf (v2)
iperf -c BOX -t 10

# iperf3
iperf3 -c BOX -t 10            # upload
iperf3 -c BOX -t 10 -R         # download
iperf3 -c BOX -u -b 10M -t 10  # UDP loss/jitter

# Crusader (CLI client, or point the Crusader GUI at BOX)
crusader test BOX
```

**Cutie:** open `http://BOX:4173` in a browser and click **Start**.

**About page:** open `http://BOX/`.
Running statistics are at `http://BOX:4173/api/stats`.

## Configuration

### Build arguments (in `docker-compose.yml` under `x-nettest.build.args`)

| Arg | Default | Meaning |
| --- | --- | --- |
| `CUTIE_REF` | `main` | Cutie branch or tag to build |
| `CRUSADER_VERSION` | `v0.3.2` | Crusader release tag ([releases](https://github.com/Zoxc/crusader/releases)) |
| `UBUNTU_VERSION` | `26.04` | Base image tag |
| `NODE_VERSION` | `24` | Node.js major version used for Cutie |

### Changing ports

Edit the `command:` line of a service, for example
`["iperf3", "-s", "-p", "5202"]`. For Cutie, change `PORT` under `environment:`.

### Cutie log level

`LOG_LEVEL` (tslog levels: 2 = debug, 3 = info, 4 = warn) is set under the `cutie`
service's `environment:`.

### Disabling a server

Start only the services you want:

```bash
docker compose up -d iperf3 crusader cutie
```

or comment the service out of `docker-compose.yml`.

## Publishing to Docker Hub

`publish.sh` builds the image for **linux/arm64 and linux/amd64** in one go and
pushes it as `<DOCKERHUB_USER>/nettest-portable`, tagged both `latest` and
with the build date (e.g. `20261114`):

```bash
docker login                               # once
cp .env.example .env                       # set DOCKERHUB_USER
./publish.sh
```

- Run it on a fast machine (e.g. a Mac with Docker Desktop). The non-native
  architecture is built under emulation, which is slow but works.
- It creates a `docker-container` buildx builder named `nettest-builder` the
  first time, because the default builder can't build several platforms at once.
- `PLATFORMS=linux/arm64 ./publish.sh` builds only some platforms.
  `PUSH=0 ./publish.sh` does a test build without pushing.
- `CUTIE_REF` and `CRUSADER_VERSION` can be set the same way to publish
  another Cutie branch or Crusader release.
- To update a board after publishing: `docker compose pull && docker compose up -d`.

## Updating

To pull the latest Cutie and rebuild everything (including Ubuntu package updates):

```bash
docker compose build --no-cache
docker compose up -d
```

To move to a newer Crusader, change `CRUSADER_VERSION` and run
`docker compose up -d --build`.

## Firewall

If the board runs a firewall (e.g. `ufw`), open these ports:

```bash
sudo ufw allow 12865/tcp          # netperf control
sudo ufw allow 5001/tcp           # iperf2
sudo ufw allow 5201               # iperf3 tcp+udp
sudo ufw allow 35481              # crusader tcp+udp
sudo ufw allow 4173/tcp           # cutie web UI
sudo ufw allow 80/tcp             # about page
sudo ufw allow 5353/udp           # mDNS
```

netperf data connections and Cutie's WebRTC use ephemeral ports, so a strict
firewall also has to allow inbound connections to the ephemeral range
(`/proc/sys/net/ipv4/ip_local_port_range`, usually 32768–60999). The easiest
fix is to allow all traffic from your test LAN:
`sudo ufw allow from 192.168.1.0/24`.

## Troubleshooting

- **Cutie page loads but no data appears.** The WebRTC connection didn't come
  up. Make sure the `cutie` service is still on `network_mode: host` and that
  the firewall allows the ephemeral UDP range from the client. Cutie uses
  Google's public STUN server (`stun.l.google.com:19302`) to gather candidates.
  On a LAN-only network with no internet access, the host candidates should
  still work.
- **"address already in use"** at startup. Something on the host already
  uses that port (e.g. an `iperf3` systemd service from the host's own package,
  or a web server such as nginx/apache already on port 80; for the About
  page, set `ABOUT_PORT` in `docker-compose.yml` to another port).
  Stop it with `sudo systemctl disable --now iperf3`, or change the port.
- **netperf works but `-t TCP_RR` / `UDP_STREAM` hangs.** The data port is
  blocked by a firewall; see above.
- **Shell inside the image:** `docker exec -it nettest-cutie bash`.
  The netperf, iperf, iperf3 and crusader client binaries are all in the image,
  so you can also test from the board itself.

- **`nettest.local` doesn't resolve.** Check `docker compose logs mdns` for
  *"Server startup complete. Host name is nettest.local"*. A warning like
  *"Detected another IPv4 mDNS stack running on this host"* means the host's
  own Avahi is still running (see the mDNS section above). If the log reports
  a name conflict, it says `nettest-2.local` or similar: another device on the
  network already uses that name, so change `MDNS_NAME`. Wi-Fi access points
  with "multicast filtering" or client isolation can also block mDNS.

## What was verified

The image was built (arm64) and the full stack was run under Docker Desktop.
Each server was then exercised with its client from inside the image:
netperf `TCP_STREAM`, iperf2 TCP, iperf3 TCP and UDP, `crusader test`,
Cutie `GET /` (200), `GET /api/stats`, and loading the `@roamhq/wrtc` native
module. The About server was tested both with no `ABOUT.md` (503 message page)
and with a sample file (headings, table, code block, quote, task list). Edits
to the file appeared on the next request, and the server ran as uid 999
(`nettest`) after binding port 80. A full browser-to-Cutie WebRTC session across a real LAN has to be
checked on the board itself.

The mDNS service started as `nettest.local` and switched to the `avahi` user.
`dig -p 5353` queries returned the A/AAAA records, both `_http._tcp` services
and their SRV records (ports 80 and 4173). A query sent to the multicast group
itself couldn't be tested under Docker Desktop's VM, so check resolution from
another machine on the board's LAN (`ping nettest.local`).
