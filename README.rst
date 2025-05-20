:orphan:

##############################
lib_xtcp: TCP/IP Library
##############################

:vendor: XMOS
:version: 6.1.0
:scope: General Use
:description: TCP/IP Library
:category: Networking
:keywords: Ethernet, MAC, MII, RMII, RGMII, SMI, TCP, UDP
:hardware: xcore.ai, xcore-200

*******
Summary
*******

A library providing two alternative TCP/UDP/IP protocol stacks for XMOS devices.
This library connects to the XMOS Ethernet library to provide layer-4 traffic
over Ethernet via MII or RGMII.

Stacks
======

This library provides two different TCP/IP stack implementations ported to the
xCORE architecture.

uIP stack
---------

The first stack ported is the uIP (micro IP) stack. The uIP stack has been
designed to have a minimal resource footprint. As a result, it has limited
performance and does not provide support for TCP windowing.

lwIP stack
----------

The second stack ported is the lwIP (lightweight IP) stack. The lwIP stack
requires more resources than uIP, but is designed to provide
better throughput and also has support for TCP windowing.

********
Features
********

 * TCP and UDP connection handling
 * Common API to selectable TCP stack, uIP/LwIP
 * DHCP, IP4LL, ICMP, IGMP support
 * Low level, event based interface for efficient memory usage
 * Supports IPv4 only, not IPv6

************
Known issues
************

 * psock.c does output ftpgroup warnings, this API is not used in this app note.


****************
Development repo
****************

  * `lib_xtcp <https://www.github.com/xmos/lib_xtcp>`_

**************
Required tools
**************

 * XMOS XTC Tools: 15.3.1

*********************************
Required libraries (dependencies)
*********************************

 * `lib_ethernet <https://www.github.com/xmos/lib_ethernet>`_
 * `lib_board_support <https://www.github.com/xmos/lib_board_support>`_

*************************
Related application notes
*************************

 * `AN00120: 100Mbps RMII ethernet application note <https://www.xmos.com/file/an00120>`_
 * `AN00199: XMOS Gigabit Ethernet application note (XK_EVK_XE216) <https://www.xmos.com/file/an00199-xmos-gigabit-ethernet-application-note>`_

The following application notes use this library:
 * `AN00121: A UDP loopback demo running on lib_xtcp application note <https://www.xmos.com/file/an00121>`_
 * `AN02044: A UDP loopback demo running on lib_xtcp on XCORE-200-EXPLORER application note <https://www.xmos.com/file/an02044>`_

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at
`http://www.xmos.com/support <http://www.xmos.com/support>`_
