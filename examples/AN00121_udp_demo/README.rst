Using XMOS TCP/IP Library for UDP-based Networking
==================================================

.. version:: 3.0.0

Summary
-------

This application note demonstrates the use of XMOS TCP/IP stack on
an XMOS multicore micro controller to communicate on an ethernet-based network.

The code associated with this application note provides an example of
using the XMOS TCP/IP (XTCP) Library and the ethernet board support
component to provide a communication framework. It demonstrates how to
broadcast and receive text messages from and to the XMOS device in the
network using the UDP stack of XTCP library. The XTCP library features
low memory footprint but provides a complete stack of various
protocols.

On an XMOS xCORE, all the endpoint activities are implemented as
concurrent real-time processes allowing the network data to be placed
on the wire or received from the wire with negligible
latency. Moreover, unlike conventional interrupt-driven processors,
the deterministic nature of event-driven XMOS processors meets the
precise timing requirements of the real-time data transmission over
networks.

Note: This application note requires an application to be run on the
host machine to test the communication with the XMOS device.

Required tools and libraries
............................

* xTIMEcomposer Tools - Version 14.0.0
* XMOS TCP/IP library - Version 6.0.0

Required hardware
.................

This application note is designed to run on an XMOS xCORE
General-Purpose 
device. 

The example code provided with the application has been implemented and tested
on the xCORE General-Purpose sliceKIT (XP-SKC-L2) with an ethernet sliceCARD (XA-SK-E100) but there is no dependancy on this board and it can be
modified to run on any development board which uses an xCORE device.

Prerequisites
.............

  - This document assumes familiarity with the XMOS xCORE architecture, the XMOS tool chain and the xC language. Documentation related to these aspects which are not specific to this application note are linked to in the references appendix.

  - For descriptions of XMOS related terms found in this document please see the *XMOS glossary* [#]_. 

  - For an overview of XTCP TCP/IP stack please see the *XMOS TCP/IP stack design guide* [#]_ for reference. 

.. [#] http://www.xmos.com/published/glossary

.. [#] https://www.xmos.com/published/xmos-tcpip-stack-design-guide


