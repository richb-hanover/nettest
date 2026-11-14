# nettest: a network test server in Docker

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

All five run from a single image (`nettest:latest`), each in its own container.
That way each server has its own logs and restarts independently.

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Multi-stage build: builds Cutie, downloads Crusader, assembles an Ubuntu 26.04 runtime |
| `docker-compose.yml` | One service per server, all on host networking, `restart: unless-stopped` |
| `.dockerignore` | Keeps the build context empty (everything is fetched from GitHub/apt) |

## Why host networking?

Every service uses `network_mode: host`. Publishing a fixed list of ports
(`-p 5201:5201` and so on) would break several of the tests:

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

## 2. Build and start

Copy this directory to the board, then:

```bash
cd nettest
docker compose up -d --build
```

The first build takes a while on a small ARM board (Cutie's `npm ci` and
`npm run build` take the most time). Later builds are cached.

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

Replace `BOX` with the board's IP address or hostname.

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
  uses that port (e.g. an `iperf3` systemd service from the host's own package).
  Stop it with `sudo systemctl disable --now iperf3`, or change the port.
- **netperf works but `-t TCP_RR` / `UDP_STREAM` hangs.** The data port is
  blocked by a firewall; see above.
- **Shell inside the image:** `docker exec -it nettest-cutie bash`.
  The netperf, iperf, iperf3 and crusader client binaries are all in the image,
  so you can also test from the board itself.

## What was verified

The image was built (arm64) and the full stack was run under Docker Desktop.
Each server was then exercised with its client from inside the image:
netperf `TCP_STREAM`, iperf2 TCP, iperf3 TCP and UDP, `crusader test`,
Cutie `GET /` (200), `GET /api/stats`, and loading the `@roamhq/wrtc` native
module. A full browser-to-Cutie WebRTC session across a real LAN has to be
checked on the board itself.
