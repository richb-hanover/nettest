# syntax=docker/dockerfile:1
#
# nettest-portable - a network test server image containing:
#   netperf (netserver), iperf (v2), iperf3, Crusader server, and Cutie.
#
# Target: Ubuntu 26.04 / Armbian 26.8 (arm64), but builds for amd64 and armhf too.
# See README.md for usage.

ARG UBUNTU_VERSION=26.04
ARG NODE_VERSION=24

# ---------------------------------------------------------------------------
# Stage 1: build Cutie (SvelteKit app, adapter-node) from GitHub
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS cutie-build

ARG CUTIE_REPO=https://github.com/richb-hanover/Cutie-Network-Quality-Test.git
ARG CUTIE_REF=main

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${CUTIE_REF}" "${CUTIE_REPO}" cutie

WORKDIR /src/cutie
RUN npm ci \
 && npm run build \
 && npm prune --omit=dev

# ---------------------------------------------------------------------------
# Stage 1b: the ABOUT.md web server, its dependency (marked) and ABOUT.md
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-bookworm-slim AS about-build

WORKDIR /opt/about
COPY about/package.json about/server.mjs ./
RUN npm install --omit=dev --no-audit --no-fund
COPY ABOUT.md ./

# ---------------------------------------------------------------------------
# Stage 2: fetch the prebuilt (static) Crusader binary for this architecture
# ---------------------------------------------------------------------------
# Runs natively on the build machine (BUILDPLATFORM) even for cross-builds:
# it only downloads a static binary for TARGETARCH, and avoids QEMU, which
# can't run Ubuntu 26.04's tar ("Function not implemented").
FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS crusader-fetch

ARG CRUSADER_VERSION=v0.3.2
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      arm64) asset="Crusader-Linux-ARM-64-bit" ;; \
      arm|armhf) asset="Crusader-Linux-ARM-32-bit" ;; \
      amd64) asset="Crusader-Linux-X86-64-bit" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/crusader.tar.gz \
      "https://github.com/Zoxc/crusader/releases/download/${CRUSADER_VERSION}/${asset}.tar.gz"; \
    tar -xzf /tmp/crusader.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${asset}/crusader" /usr/local/bin/crusader

# ---------------------------------------------------------------------------
# Stage 3: runtime image
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION}

ARG NODE_VERSION=24
ARG IMAGE_VERSION=dev
ARG CUTIE_REF=main
ARG CRUSADER_VERSION=v0.3.2

# Published to Docker Hub as <user>/nettest-portable (see publish.sh)
LABEL org.opencontainers.image.title="nettest-portable" \
      org.opencontainers.image.description="Portable network test server: netperf, iperf, iperf3, Crusader, Cutie, an ABOUT.md page and mDNS (nettest.local)" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      io.nettest.cutie-ref="${CUTIE_REF}" \
      io.nettest.crusader-version="${CRUSADER_VERSION}"

# netperf lives in "multiverse" on some Ubuntu releases; the Ubuntu base image
# enables all components, so a plain apt-get install works.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      netperf \
      iperf \
      iperf3 \
      ca-certificates \
      tini \
      avahi-daemon \
 && rm -rf /var/lib/apt/lists/*

# Node.js runtime for Cutie, copied from the official image used to build it
COPY --from=cutie-build /usr/local/bin/node /usr/local/bin/node

# Crusader
COPY --from=crusader-fetch /usr/local/bin/crusader /usr/local/bin/crusader

# Cutie: built app + production dependencies (incl. the @roamhq/wrtc native module)
COPY --from=cutie-build /src/cutie/build        /opt/cutie/build
COPY --from=cutie-build /src/cutie/node_modules /opt/cutie/node_modules
COPY --from=cutie-build /src/cutie/package.json /opt/cutie/package.json

# ABOUT.md web server (port 80) and the ABOUT.md it serves (/opt/about/ABOUT.md)
COPY --from=about-build /opt/about /opt/about

# mDNS responder start script (advertises <MDNS_NAME>.local via avahi-daemon)
COPY --chmod=0755 mdns/start.sh /opt/mdns/start.sh

# Run everything as an unprivileged user; none of the default ports need root.
RUN useradd --system --create-home --home-dir /home/nettest --shell /usr/sbin/nologin nettest
USER nettest
WORKDIR /home/nettest

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4173 \
    LOG_LEVEL=3

# Documentation only: docker-compose.yml uses host networking.
#   12865/tcp  netperf control (data connections use ephemeral ports)
#   5001/tcp   iperf (v2)
#   5201/tcp   iperf3 (TCP and UDP)
#   35481/tcp+udp  Crusader server
#   4173/tcp   Cutie web UI (WebRTC uses ephemeral UDP ports)
#   80/tcp     ABOUT.md page
EXPOSE 12865 5001 5201 5201/udp 35481 35481/udp 4173 80

ENTRYPOINT ["/usr/bin/tini", "--"]
# Default command; docker-compose.yml overrides this for each service.
CMD ["node", "/opt/cutie/build"]
