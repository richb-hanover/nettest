# About nettest-portable

This computer hosts a number of servers
that are useful for local network testing.
Because you connect it by Ethernet to your local
network, you avoid the latency, packet loss,
and other vagaries of the wider internet.
See the list of test services below.

_Version 0.1.2 - 16Nov2026_

## Using nettest-portable

1. After it is [installed](#installing-nettest-portable),
   connect the **nettest-portable**
  computer to an Ethernet port
  "near the center" of your network and power it up.
2. It grabs a DHCP address and
   advertises the mDNS name `nettest.local`
3. Connect to this page
   [http://nettest.local](http://nettest.local)
   to see if it's working.
4. Use `nettest.local` as the server for
   various network tests.

## Test services available

**nettest-portable** runs many servers:

* **[iperf (v2)](https://iperf.fr/iperf-doc.php#doc)**
  ... and ...
  **[iperf3](https://iperf.fr/iperf-doc.php#3doc)**
  ... and ... 
  **[netperf](https://hewlettpackard.github.io/netperf/)**
  are "speed test" programs that check
  data transfer rates between hosts.
  Although they have the same spirit,
  they have evolved separately,
  have very different options, and are **not** compatible.
  Different test tools specify their
  own backend servers.
  This docker container hosts them all.

* **[Cutie Network Quality Test](https://github.com/richb-hanover/Cutie-Network-Quality-Test/blob/main/README.md)** 
  A web-based monitor of MOS Quality, packet loss,
  and latency/jitter.
  It uses WebRTC to make these fine-grained
  measurements.
  Browse to [http://nettest.local:4173](http://nettest.local:4173) to try it out.

* **[Crusader Throughput and Latency Tester](https://github.com/Zoxc/crusader/blob/master/README.md)** 
  A Windows, Mac, Linux app that provides detailed
  measurements of transfer rates, latency,
  and packet loss.
  Download the pre-built binaries
  (GUI or command-line) from the
  [Releases tab](https://github.com/Zoxc/crusader/releases/tag/v0.3.2),
  then test against `nettest.local`

## Installing nettest-portable

Build a Linux computer
(maybe a Raspberry Pi or other small device)
with a recent OS and install Docker.
Then run these commands:

```bash
mkdir nettest-portable && cd nettest-portable
curl -fsSLO https://raw.githubusercontent.com/richb-hanover/nettest-portable/main/docker-compose.yml
docker compose pull && docker compose up -d
```

To update to the latest release later, run this in the same directory:

```bash
cd nettest-portable
docker compose pull && docker compose up -d
```

## About nettest-portable

This Docker container was created by
[Rich Brown](mailto:richb.hanover@gmail.com)
because he needed a tool to test his home network,
and wondered why such a thing didn't already exist.

Read more of Rich's ruminations at his blog:
[Random Neurons Firing](https://randomneuronsfiring.com).
