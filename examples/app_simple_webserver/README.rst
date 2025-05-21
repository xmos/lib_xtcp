:orphan:

###########################################
A simple webserver demo running on lib_xtcp
###########################################

:vendor: XMOS
:version: 1.0.0
:scope: Example
:description: TCP/IP simple webserver example
:category: Networking
:keywords: Ethernet, MAC, RGMII, SMI, TCP, UDP
:hardware: XK-EVK-XE216

********
Overview
********

This application note demonstrates the use of XMOS TCP/IP stack on
an XMOS multicore micro controller to communicate on an ethernet-based network.

The code associated with this application note provides an example of
using the XMOS TCP/IP (XTCP) Library and the ethernet board support
component to provide a communication framework. It demonstrates how to
broadcast and receive text messages from and to the XMOS device in the
network using the TCP stack of XTCP library. The XTCP library features
low memory footprint but provides a complete stack of various
protocols.

Ethernet connectivity is an essential part of the explosion of connected 
devices known collectively as the Internet of Things (IoT). XMOS technology is
perfectly suited to these applications - offering future proof and reliable 
ethernet connectivity whilst offering the flexibility to interface to a huge 
variety of "Things".

The code associated with this application note provides an example of using
the TCP and Ethernet Libraries to provide a simple webserver using a Reduced
Gigabit Media Independent Interface (RGMII) and MAC interface for 1000Mbps.

Note: This application note requires an application to be run on the
host machine to test the communication with the XMOS device.

************
Key features
************

 * RMII L2 MAC interface
 * SMI serial interface
 * Selectable TCP stack, uIP/LwIP
 * "hello,world!" style demo webserver

************
Known issues
************

 * psock.c does output ftpgroup warnings, this API is not used in this app note.

**************
Required tools
**************

 * XMOS XTC Tools: 15.3.1

*********************************
Required libraries (dependencies)
*********************************

 * `lib_xtcp <https://www.github.com/xmos/lib_xtcp>`_
 * `lib_board_support <https://www.github.com/xmos/lib_board_support>`_

*************
Related notes
*************

 * `AN00120: 100Mbps RMII ethernet application note <https://www.xmos.com/file/an00120>`_
 * `AN00199: XMOS Gigabit Ethernet application note (XK_EVK_XE216) <https://www.xmos.com/file/an00199-xmos-gigabit-ethernet-application-note>`_

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at: http://www.xmos.com/support
