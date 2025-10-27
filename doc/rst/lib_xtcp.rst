
########################
lib_xtcp: TCP/IP Library
########################

|newpage|

************
Introduction
************

This document details the XMOS TCP library ``lib_xtcp`` which allows use of TCP 
and UDP traffic over Ethernet.

The following sections of the document describe the general usage and behaviour 
of the library, followed by a detailed usage with an example application and 
then detailed descriptions of the APIs.

This document assumes familiarity with the XMOS xcore architecture, Ethernet, and
TCP/IP along with the XMOS XTC toolchain and the XC language.

``lib_xtcp`` is intended to be used with the `XCommon CMake <https://www.xmos.com/file/xcommon-cmake-documentation/?version=latest>`_
, the `XMOS` application build and dependency management system.

This library is for use with `xcore-200` series (XS2 architecture) or `xcore.ai` 
series (XS3 architecture) devices, previous generations of xcore devices
(i.e. XS1 architecture) are supported, but all examples and app-notes target newer devices.

Terms
=====

The terms used in this document can appear confusing as `client` and `server` 
can both be used in two different ways. Firstly, for the an XC interface there are
clients and servers, see :ref:`xtcp_client_api` as an example. The client 
being application and the server being the ``lib_xtcp`` stack. This usage is 
commonly used throughout this document. Secondly, there are TCP/IP clients and 
servers, these are referred to as a local host or remote host, or in context 
such as `DHCP server` or `HTTP server`.

|newpage|

********
Overview
********

The TCP/IP library provides OSI layer 3 and 4 features. Client applications 
built on ``lib_xtcp`` can provide layers 5-7 features as needed, such as the 
HTTP example provided in the library's example ``app_simple_webserver``, see 
:ref:`getting_Started_section` section.

.. list-table:: lib_xtcp and the OSI Layer Model
  :width: 80%
  :header-rows: 1

  * - OSI Layers
    - Addressing
    - xcore libraries
  * - Application
    - e.g. HTTP/URL
    - (lib_xtcp client) app_simple_webserver
  * - Presentation
    - application specific
    - lib_xtcp client application
  * - Session
    - application specific
    - lib_xtcp client application
  * - Transport
    - Port
    - lib_xtcp
  * - Network
    - IP
    - lib_xtcp
  * - Data link
    - MAC
    - lib_ethernet (MAC)
  * - Physical
    - PHY
    - lib_ethernet (PHY)


The TCP/IP stack runs in a task implemented in the
:c:func:`xtcp_lwip` function which implements TCP/IP functionality using the lwIP stack.

This task connects to either the RMII/RGMII MAC components or the MII component
in the Ethernet library ``lib_ethernet``.
See the figures :ref:`tcp_task_mac_section` and :ref:`tcp_task__mii_section`
and the Ethernet library user guide for details on these components.

.. _tcp_task_mac_section:

.. uml::
  :caption: XTCP task diagram
  :align: center
  :width: 80%

  () "client"
  () "lib_xtcp"
  () "ethernet mac" as ethernet

  client - lib_xtcp: xtcp_if

  lib_xtcp - ethernet: ethernet_cfg_if
  lib_xtcp - ethernet: ethernet_rx_if
  lib_xtcp - ethernet: ethernet_tx_if

Or direct to the MII component,

.. _tcp_task__mii_section:

.. uml::
  :caption: XTCP task diagram (MII)
  :align: center
  :width: 60%

  () "client"
  () "lib_xtcp"
  () "mii"

  client - lib_xtcp: xtcp_if

  lib_xtcp - mii: mii_if

Clients can interact with the TCP/IP stack via interfaces connected
to the component using the interface functions described in
:ref:`xtcp_client_api`.

If the application has no need to direct layer 2 traffic to the
Ethernet MAC then the most resource efficient approach is to connect
the ``xtcp`` component directly to the MII layer component.

.. _ip_configuration_section:

IP Configuration
================

The library server will determine its IP configuration based on the ``xtcp_ipconfig_t``
configuration passed into the :c:func:`xtcp_lwip` task (see section :ref:`xtcp_server_api`).
If an address is supplied then that address will be used (a static IP address configuration):

.. code-block:: C

  xtcp_ipconfig_t ipconfig = {
    { 192, 168,   0, 2 }, // ip address
    { 255, 255, 255, 0 }, // netmask
    { 192, 168,   0, 1 }  // gateway
  };

If no address is supplied then the server will first
try to find a DHCP server on the network to obtain an address
automatically. If it cannot obtain an address from DHCP, it will determine
a link local address (in the range 169.254/16) automatically using the
Zeroconf IPV4LL protocol.

To use dynamic address, the :c:func:`xtcp_lwip`
function can be passed a structure with an IP address that is all zeros:

.. code-block:: C

  xtcp_ipconfig_t ipconfig = {
    { 0, 0, 0, 0 }, // ip address
    { 0, 0, 0, 0 }, // netmask
    { 0, 0, 0, 0 }  // gateway
  };

.. _events_and_connections_section:

Events and Connections
======================

The TCP/IP application stack client interface (see :ref:`xtcp_client_api`) is a
low-level event based interface. This is to allow applications to manage 
buffering and connections in the most efficient way possible for the application.

Each client will receive packet ready *events* from the server to indicate that
the server has new data for that client. The client then collects the packet
using the :c:func:`get_packet` call.

The packets sent from the server can be either data or control packets. The type
of packet is indicated in the connection state :c:member:`event` member. The
possible packet types are defined in :ref:`lib_xtcp_event_types`.

A client will typically handle its connection to the XTCP server in the following
manner:

.. code-block:: C

  xtcp_connection_t conn;
  char buffer[ETHERNET_MAX_PACKET_SIZE];
  unsigned data_len;
  select {
    case i.xtcp.packet_ready():
      i_xtcp.get_packet(conn, buffer, ETHERNET_MAX_PACKET_SIZE, data_len);
      // Handle event
      switch (conn.event) {
        ...
      }
      break;
    }

The client can also call interface functions to initiate new connections, manage
the connection and send or receive data.

If the client is handling multiple connections then the server may
interleave events for each connection so the client has to hold a
persistent state for each connection.

The connection and event model is the same from both TCP connections
and UDP connections. Full details of both the possible events and
possible commands can be found in :ref:`lib_xtcp_api`.

New Connections
===============

New connections are made in two different ways. Either the
:c:func:`connect` function is used to initiate a connection with
a remote host or the :c:func:`listen` function is
used to listen on a port for remote hosts to connect to the application.
In either case once a connection is established then the
:c:member:`XTCP_NEW_CONNECTION` event is received by the client.

By convention with POSIX sockets, a listening UDP connection merely reports
data received on the socket, independent of the source IP address.  In
XTCP, a :c:member:`XTCP_NEW_CONNECTION` event is sent each time data
arrives from a new source.  The API function :c:func:`close`
should be called after the connection is no longer needed.

TCP and UDP
===========

The XTCP API treats UDP and TCP connections in the same way. The only
difference is when the protocol is specified on initializing
connections with the interface :c:func:`connect` or :c:func:`listen`
functions.

For example, a client that wishes to listen for HTTP requests over TCP 
connections on port 80:

.. code-block:: C

  i_xtcp.listen(80, XTCP_PROTOCOL_TCP);

A client could create a new UDP connection to port 15333 on a machine at
192.168.0.2 using:

.. code-block:: C

  xtcp_ipaddr_t addr = { 192, 168, 0, 2 };
  i_xtcp.connect(15333, addr, XTCP_PROTOCOL_UDP);

Receiving Data
==============

When data is received for a client the server will indicate that there is a
packet ready and the :c:func:`get_packet` call will indicate that the event
type is :c:member:`XTCP_RECV_DATA` and the packet data will have been returned
to the :c:func:`get_packet` call.

Data is sent from the XTCP server to client as the UDP or TCP packets arrive
from the ethernet MAC. There is no buffering in the server so it will wait for the client
to handle the event before processing new incoming packets.

Sending Data
============

When sending data, the client is responsible for dividing the data
into chunks for the server and re-transmitting the previous chunk if a
transmission error occurs.

.. note:: Note that re-transmission may be needed on
          both TCP and UDP connections. On UDP connections, the
          transmission may fail if the server has not yet established
          a connection between the destination IP address and layer 2
          MAC address.

The client sends a packet by calling the :c:func:`send` interface function. 
A `resend` is done by calling :c:func:`send` function with the same data buffer as
the previous send.

.. note:: The maximum buffer size that can be sent in one call to
          `xtcp_send` is contained in the `mss` field of the connection
          structure relating to the event.

After this data is sent to the server, two things can happen, shown in 
figure :ref:`tcp_send_sequence_section`: Either
the server will respond with an :c:member:`XTCP_SENT_DATA` event, in
which case the next chunk of data can be sent. Or with an
:c:member:`XTCP_RESEND_DATA` event in which case the client must
re-transmit the previous chunk of data.

.. _tcp_send_sequence_section:

.. uml::
  :caption: Example TCP/IP send sequence
  :align: center
  :width: 40%

  CLIENT -> SERVER: i_xtcp.connect()
  SERVER --> CLIENT: XTCP_NEW_CONNECTION

  CLIENT -> SERVER: i_xtcp.send(1)
  SERVER --> CLIENT: XTCP_RESEND_DATA

  CLIENT -> SERVER: i_xtcp.send(1)
  SERVER --> CLIENT: XTCP_SENT_DATA

  CLIENT -> SERVER: i_xtcp.send(2)
  SERVER --> CLIENT: XTCP_SENT_DATA

  CLIENT -> SERVER: i_xtcp.close()


Link Status Events
==================

As well as events related to connections. The server may also send
link status events to the client. The events :c:member:`XTCP_IFUP` and
:c:member:`XTCP_IFDOWN` indicate to a client when the link goes up or down.

Server Configuration
====================

The server is configured via arguments passed to server task, see section 
:ref:`xtcp_server_api` (:c:func:`xtcp_lwip`) and the defines 
described in Section :ref:`sec_config_defines`.

Stack Configuration
===================

The underlying stack configuration can by modified by including optional header
files in the application. One or both of the following, these will override the
LwIP build settings. See :ref:`sec_config_defines`.

* xtcp_client_conf.h
* xtcp_conf.h

|newpage|

.. _usage_section:

*****
Usage
*****

Using ``lib_xtcp``
==================

To use this library, include ``lib_xtcp`` in the application's
``APP_DEPENDENT_MODULES`` list in `CMakeLists.txt`, for example:

.. code-block:: cmake

  set(APP_DEPENDENT_MODULES "lib_xtcp")

All functions and types can be found in the ``xtcp.h`` header file:

.. code-block:: C

  #include <xtcp.h>

.. _getting_Started_section:

Getting Started
===============

The app_simple_webserver example is provided to show how the library can 
use TCP traffic for a very simple HTTP server.

The example targets the XCORE-200-EXPLORER dev-kit and 1000BASE-T ethernet 
with an RGMII PHY.

The ``lib_xtcp`` uses a third-party TCP/IP stack, the ``LwIP`` stack. This is built automatically
when the library is built. ``lib_xtcp`` uses one thread to run the TCP/IP stack and uses around 50 kB of code
and 30kB of data, and the application client runs in another thread. The memory usage will vary
depending on the configuration of the stack and the application.


By default the The IP address for the XCORE will be automatically assigned via 
DHCP if :c:struct:`xtcp_ipconfig_t` ``ipconfig = { ... };`` in ``main.xc`` is 
filled with zeros. Otherwise, to set a static IP address, insert the IPv4 
address into the first row of ``ipconfig`` and the subnet mask to the second 
row, the subnet mask is typically ``{ 255, 255, 255, 0 }``. For details please 
see section :ref:`ip_configuration_section`

The excerpt from the example web server shown below shows how to configure the 
``lib_xtcp`` server with the application client here as `xhttpd`

.. code-block:: C

  int main(void) {
    xtcp_if i_xtcp[NUM_XTCP_CLIENTS];
    smi_if i_smi;
    ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
    ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
    ethernet_tx_if i_tx[NUM_ETH_CLIENTS];

    par {
      // ethernet driver setup here...

      // SMI/ethernet phy driver
      on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

      on tile[0]: xtcp_lwip(i_xtcp, NUM_XTCP_CLIENTS, null,
                            i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                            mac_address_phy, null, ipconfig);

      // HTTP server application
      on tile[0]: xhttpd(i_xtcp[XTCP_TO_HTTP]);
    }
    return 0;
  }

The function :c:func:`xhttpd`, called from main will listen for a TCP connection
on port 80 and shows an example of handling the events and data flowing to and 
from the TCP stack. For details please see section 
:ref:`events_and_connections_section` and the notifications are defined in 
:ref:`lib_xtcp_event_types`.

.. code-block:: C

  void xhttpd(client xtcp_if i_xtcp)
  {
    printstr("**WELCOME TO THE SIMPLE WEBSERVER DEMO**\n");

    // Initiate the HTTP state
    httpd_init(i_xtcp);

    // Loop forever processing TCP events
    while(1) {
      xtcp_connection_t conn;
      char rx_buffer[RX_BUFFER_SIZE];
      unsigned data_len;

      select {
        case i_xtcp.packet_ready(): {
          i_xtcp.get_packet(conn, rx_buffer, RX_BUFFER_SIZE, data_len);

          if (conn.local_port == 80) {
            // HTTP connections
            switch (conn.event) {
              ...

The project supports CMake by default, to build the project first configure then 
build with,

.. code-block:: shell

  cd lib_xtcp
  cd examples

  cmake -B build -G "Unix Makefiles"
  
  xmake -j -C build

Once built run with,

.. code-block:: shell

  xrun --xscope app_simple_webserver/bin/app_simple_webserver.xe

When running and with the dev-kit connected to the same network has the computer,
open a browser window and enter the address printed on the xrun 
terminal. The browser will display a short message, "Hello World!".

|newpage|

*****************
Configuration API
*****************

.. _sec_config_defines:

Configuration Defines
=====================

Configuration defines can either be set by adding the a command line
option to the build flags in the application CMakelists file
(i.e. ``-DDEFINE=VALUE``) or by adding the file
``xtcp_client_conf.h`` into the application and then putting
``#define`` directives into that header file (which will then be read
by the library on build).

``XTCP_CLIENT_BUF_SIZE``
       The buffer size used for incoming packets. This has a maximum
       value of 1472 which can handle any incoming packet. If it is
       set to a smaller value, larger incoming packets will be truncated. Default
       is 1472.

.. doxygendefine:: MAX_XTCP_CLIENTS

.. doxygendefine:: CLIENT_QUEUE_SIZE

.. doxygenfunction:: xtcp_configure_mac

|newpage|

.. _lib_xtcp_api:

**************
Functional API
**************

See :ref:`usage_section` section and :ref:`getting_Started_section` for 
details on usage of the following.

Data Structures/Types
=====================

.. doxygentypedef:: xtcp_ipaddr_t

.. doxygenstruct:: xtcp_ipconfig_t

.. doxygenenum:: xtcp_protocol_t

|newpage|

.. _lib_xtcp_event_types:

Event types
===========

.. doxygenenum:: xtcp_event_type_t

|newpage|

.. _xtcp_server_api:

Server API
==========

.. doxygenfunction:: xtcp_lwip

|newpage|

.. _xtcp_client_api:

Client API
==========

.. doxygengroup:: xtcp_if
