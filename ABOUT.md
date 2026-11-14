# About nettest.local

This computer hosts a number of utilities
that are useful for local network testing.
See the list of test servers below.

To create the **nettet**, build a small Linux computer
with a recent OS and install Docker.
Then use 

To use it:

1. Connect the **nettest** computer to an Ethernet port
  "near the center" of your network and power it up.
2. It advertises the name `nettest.local` for all tests.
3. You can see this page at [http://nettest.local](http://nettest.local)

## Test servers available

* **[Cutie Network Quality Test](https://github.com/richb-hanover/Cutie-Network-Quality-Test)** 
  Browse to [http://nettester.local:4173](http://nettester.local:4173)

* **[Crusader Throughput and Latency Tester](https://github.com/Zoxc/crusader)** 
  Download the client (GUI or command-line) from the
  [Releases tab]([https://github.com/Zoxc/crusader](https://github.com/Zoxc/crusader/releases/tag/v0.3.2)), then test against
  `nettest.local`

* **[iperf (v2)](https://iperf.fr/iperf-doc.php#doc)**
  ... and ...
  **[iperf3](https://iperf.fr/iperf-doc.php#3doc)**
  ... and ... 
  **[netperf](hewlettpackard.github.io/netperf)**
  are "speed test" programs to check speeds between hosts.
  Although they have the same spirit,
  they have evolved separately and are **not** compatible.
  Different tools specify different backend servers.
  This docker container hosts them all.
  
