TCP/IP Library
==============

Overview
--------

A library providing two alternative TCP/UDP/IP protocol stacks for XMOS devices.
This library connects to the XMOS Ethernet library to provide layer-3 traffic
over Ethernet via MII or RGMII.

Features
........

   * TCP and UDP connection handling
   * DHCP, IP4LL, ICMP, IGMP support
   * Low level, event based interface for efficient memory usage
   * Supports IPv4 only, not IPv6

Stacks
......

This library provides two different TCP/IP stack implementations ported to the
xCORE architecture.

uIP stack
+++++++++

The first stack ported is the uIP (micro IP) stack. The uIP stack has been
designed to have a minimal resource footprint. As a result, it has limited
performance and does not provide support for TCP windowing.

lwIP stack
++++++++++

The second stack ported is the lwIP (lightweight IP) stack. The lwIP stack
requires more resources than uIP, but is designed to provide
better throughput and also has support for TCP windowing.

Typical Resource Usage
......................

.. resusage::

  * - configuration: UIP
    - globals: xtcp_ipconfig_t ipconfig = {
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 }
               };
               char mac_addr[6] = {0};
    - locals: interface mii_if i_mii; xtcp_if i_xtcp[1];
    - fn: xtcp_uip(i_xtcp, 1, i_mii,
                   null, null, null,
                   null, 0, mac_addr, null, ipconfig);
    - pins: 0
    - ports: 0
  * - configuration: LWIP
    - globals: xtcp_ipconfig_t ipconfig = {
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 }
               };
               char mac_addr[6] = {0};
    - locals: interface mii_if i_mii; xtcp_if i_xtcp[1];
    - fn: xtcp_lwip(i_xtcp, 1, i_mii,
                   null, null, null,
                   null, 0, mac_addr, null, ipconfig);
    - pins: 0
    - ports: 0
    - target: XCORE-200-EXPLORER


Software version and dependencies
.................................

.. libdeps::

Related application notes
.........................

The following application notes use this library:

  * AN00121 - Using the XMOS TCP/IP library
