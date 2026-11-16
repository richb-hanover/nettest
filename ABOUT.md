# About nettest-portable

This computer hosts a number of utilities
that are useful for local network testing.
Because it is directly connected to your local
network, you avoid the latency, packet loss,
and other vagaries of the wider internet.
See the list of test services below.

_Version 0.1.1 - 16Nov2026_

## To build nettest-portable

Build a small Linux computer
with a recent OS and install Docker.
Then run these commands:

```bash
mkdir nettest-portable && cd nettest-portable
curl -fsSLO https://raw.githubusercontent.com/richb-hanover/nettest-portable/main/docker-compose.yml
docker compose pull && docker compose up -d
```

To update to the latest release later, run this in the same directory:

```bash
docker compose pull && docker compose up -d
```

## Using nettest-portable

1. After it is built, connect the **nettest-portable**
  computer to an Ethernet port
  "near the center" of your network and power it up.
2. It advertises the name `nettest.local` for all tests.
3. Connect to this page
   [http://nettest.local](http://nettest.local)
   to see if it's working.

## Test services available

**nettest-portable** runs several servers for testing:

* **[Cutie Network Quality Test](https://github.com/richb-hanover/Cutie-Network-Quality-Test)** 
  Browse to [http://nettest.local:4173](http://nettest.local:4173)

* **[Crusader Throughput and Latency Tester](https://github.com/Zoxc/crusader)** 
  Download the client (GUI or command-line) from the
  [Releases tab](https://github.com/Zoxc/crusader/releases/tag/v0.3.2), then test against
  `nettest.local`

* **[iperf (v2)](https://iperf.fr/iperf-doc.php#doc)**
  ... and ...
  **[iperf3](https://iperf.fr/iperf-doc.php#3doc)**
  ... and ... 
  **[netperf](https://hewlettpackard.github.io/netperf/)**
  are "speed test" programs that check speeds between hosts.
  Although they have the same spirit,
  they have evolved separately,
  have very different options, and are **not** compatible.
  Different tools specify different backend servers.
  This docker container hosts them all.
  
