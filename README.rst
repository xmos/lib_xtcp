TCP/IP Library
==============

Overview
--------

A TCP/UDP/IP protocol stack for XMOS devices. This library connects to
the XMOS Ethernet library to provide layer-3 traffic over Ethernet via
MII or RGMII.

Features
........

   * TCP + UDP connection handling
   * DHCP, IP4LL, ICMP, IGMP support
   * Low level, event based interface for efficient memory usage
   * Based on the open-source uIP stack
   * Currently, the library does not officially support IPv6. However,
     experimental code for IPv6 support is contained in the
     library. Contact XMOS for more details if you require IPv6.
