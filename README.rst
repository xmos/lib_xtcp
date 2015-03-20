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

Typical Resource Usage
......................

.. resusage::

  * - configuration: Standard
    - globals: xtcp_ipconfig_t ipconfig = {
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 }
               };
               char mac_addr[6] = {0};
    - locals: interface mii_if i_mii; chan c_xtcp[1];
    - fn: xtcp(c_xtcp, 1, i_mii,
               null, null, null,
               null, 0, mac_addr, null, ipconfig);
    - pins: 0
    - ports: 0


Software version and dependencies
.................................

.. libdeps::

Related application notes
.........................

The following application notes use this library:

  * AN00121 - Using the XMOS TCP/IP library
