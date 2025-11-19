:orphan:

########################
lib_xtcp: TCP/IP Library
########################

:vendor: XMOS
:version: 7.0.0
:scope: General Use
:description: TCP/IP Library
:category: Networking
:keywords: Ethernet
:devices: xcore.ai, xcore-200

*******
Summary
*******

``lib_xtcp`` is a library providing implementations of the Ethernet transport
layer, designed to support host-to-host network communication by handling data
exchange typically using TCP or UDP protocols.
It provides a software defined Ethernet transport stack implementation that 
connects to and runs on the XMOS Ethernet library ``lib_ethernet`` to support 
layer-4 traffic over Ethernet via MII or RGMII, at 10/100/1000 Mb/s Ethernet data 
rates.

The library provides two alternative TCP/UDP/IP protocol stacks for XMOS devices.
See the following section for further details.

TCP/IP Stack
============

The TCP/IP stack used is the third-party lwIP (lightweight IP) stack ported to the
xcore architecture. The lwIP stack is designed to provide good throughput and also has support for TCP windowing.
Throughput in excess of 50 Mbps can be achieved using RMII with this stack on xcore.ai devices.

Repository Submodule
====================

Please note: the TCP/IP stack is included as a submodule, if cloning the repository please ensure to
clone with ``--recurse-submodules`` or run ``git submodule update --init --recursive`` after cloning.

********
Features
********

* TCP and UDP connection handling
* Common API to TCP/IP stack, LwIP
* TCP, UDP, DHCP, ICMP, IGMP
* Low level, event based interface for efficient memory usage
* Supports IPv4 only, not IPv6

************
Known issues
************

* Only one network interface supported at a time with an RMII/RGMII MAC. This needs support from the underlying ``lib_ethernet`` library (https://github.com/xmos/lib_xtcp/issues/51).
* Support for IP4LL have been disabled.
* Only supports real-time variants of ``lib_ethernet`` MACs, due to use of timestamps of sent and received packets.

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

* `lib_ethernet <https://www.xmos.com/libraries/lib_ethernet>`_
* `lib_otpinfo <https://www.xmos.com/libraries/lib_otpinfo>`_
* `lib_logging <https://www.xmos.com/libraries/lib_logging>`_
* `lib_random <https://www.xmos.com/libraries/lib_random>`_
* `lib_xassert <https://www.xmos.com/libraries/lib_xassert>`_

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
