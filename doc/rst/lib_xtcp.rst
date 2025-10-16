
########################
lib_xtcp: TCP/IP Library
########################

|newpage|

************
Introduction
************

This document details the `XMOS` TCP library ``lib_xtcp`` which allows use of TCP 
and UDP traffic over Ethernet.

The following sections of the document describe the general usage and behaviour 
of the library, followed by a detailed usage with an example application and 
then detailed descriptions of the APIs.

This document assumes familiarity with the `XMOS` xcore architecture, Ethernet, and
TCP/IP along with the `XMOS` XTC toolchain and the XC language.

``lib_xtcp`` is intended to be used with the `XCommon CMake <https://www.xmos.com/file/xcommon-cmake-documentation/?version=latest>`_
, the `XMOS` application build and dependency management system.

This library is for use with `xcore-200` series (XS2 architecture) or `xcore.ai` 
series (XS3 architecture) devices, previous generations of xcore devices
(i.e. XS1 architecture) are supported, but all examples and app-notes target newer devices.

Terms
=====

The terms used in this document can appear confusing as `client` and `server` 
can both be used in two different ways. Firstly, for an XC interface there are
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


TCP/IP stack
============

In earlier releases of ``lib_xtcp``, the TCP/IP stack used was selectable between LwIP and uIP.
From version 7.0.0 onwards, only the LwIP stack is supported with 2 configurations,
`standard` and `minimal`. The `standard` configuration is the default and provides better performance
by having a larger memory footprint.

The TCP/IP stack runs in a task implemented in the
:c:func:`xtcp_lwip` function which implements TCP/IP functionality using the `lwIP <https://github.com/xmos/lwip>`_ stack.

Ethernet MAC/PHY
================

This task connects to either the RMII/RGMII MAC components or the MII component
in the Ethernet library ``lib_ethernet``.
See the figures :numref:`tcp_task_mac_section` and :numref:`tcp_task__mii_section`
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

Clients can interact with the TCP/IP stack via the interface
of the ``lib_xtcp`` component using the interface functions described in
:ref:`xtcp_client_api`.

.. note:: The ``lib_xtcp`` will only build against `real-time` MACs, due to the
   use of ``lib_ethernet`` timestamps in the TCP/IP stack.

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

To use dynamic addressing via DHCP, the :c:func:`xtcp_lwip`
function can be passed a structure with an IP address that is all zeros:

.. code-block:: C

  xtcp_ipconfig_t ipconfig = {
    { 0, 0, 0, 0 }, // ip address
    { 0, 0, 0, 0 }, // netmask
    { 0, 0, 0, 0 }  // gateway
  };

.. note:: Note that the DHCP client will retry indefinitely
          until it obtains an address. This means that if there is no DHCP
          server on the network then the stack will not be able to
          send or receive any packets.

.. _events_and_connections_section:

Events and Connections
======================

The TCP/IP client application stack interface (see :ref:`xtcp_client_api`) is a
low-level event based interface. This is to allow applications to manage 
buffering and connections in the most efficient way possible for the application.

Each client will receive *event* notifications from the server to indicate that
the server has either new data or network notifications for that client. The client then retrieves the
event using the :c:func:`get_event` call. This returns the event type as a :c:enum:`xtcp_event_type_t`, detailed in :ref:`lib_xtcp_event_types`,
and a connection id as an out parameter. The connection id is used to identify
the socket that the event relates to.

A client will typically handle its connection to the XTCP server in the following
manner:

.. code-block:: C

  int32_t conn_id;
  char buffer[ETHERNET_MAX_PACKET_SIZE];
  unsigned data_len;
  select {
    case i_xtcp.event_ready():
      xtcp_event_type_t event = i_xtcp.get_event(conn_id);
      // Handle events
      switch (event) {
        ...
        case XTCP_RECV_DATA:
          int32_t length = i_xtcp.recv(conn_id, buffer, ETHERNET_MAX_PACKET_SIZE);
          if (length > 0) {
            // process data in buffer
          } else {
            // handle error
          }
          ...
          break;
        ...
      }
      break;
    }

The client can also call interface functions to initiate new connections, manage
the connection and send or receive data.

If the client is handling multiple connections then the server may
interleave events for each connection so the client may have to hold
persistent state for each connection.

At ``lib_xtcp`` version 7.0.0, the interface API changed to make the data handling easier for clients.
The old ``xtcp_connection_t`` structure is no longer used and instead the connection `id` is passed
as an out parameter from the :c:func:`get_event` function and as an in parameter to the other interface functions.

Thus, the connection and event model is now different for TCP connections and UDP connections.
Full details of both the possible events and possible commands can be found in :ref:`lib_xtcp_api`.
See the following sections for details of handling new connections, sending and receiving data using UDP and TCP.

Creating a socket
=================

To create a new socket, the client must call the :c:func:`socket` function with the desired protocol (TCP or UDP).
This function will return a connection ID that can be used to refer to the socket in future calls.

.. note:: This was added in v7.0.0 and is the way to create a new socket.
          In previous versions, the socket was created implicitly by the interface.

New Connections
===============

New connections are made in two different ways. Either the :c:func:`connect` function is used to initiate a connection with
a remote host or the :c:func:`listen` function is used to listen on a port for remote hosts to connect to.

TCP connections
---------------

On a TCP socket, calling :c:func:`connect` will begin the process of establishing a connection and when the :c:member:`XTCP_NEW_CONNECTION` event is received by the client the connection can be used.
And respectively, calling :c:func:`listen` will allow the client to wait for remote host connections, when each host connects the :c:member:`XTCP_ACCEPTED` event is received by the client and the connection can be used.
After either event the socket can be considered `connected` by the client and send and receive data as needed. Using the functions :c:func:`send` and :c:func:`recv`.

For example, a client that wishes to listen for HTTP requests over TCP 
connections on port 80:

.. code-block:: C

  static const xtcp_ipaddr_t any_addr = { 0, 0, 0, 0 };
  int32_t id = i_xtcp.socket(XTCP_PROTOCOL_TCP);
  xtcp_error_code_t listen_result = i_xtcp.listen(id, 80, any_addr);

A note on handling IDs on TCP connections
-----------------------------------------

When making a new connection with :c:func:`connect`, the same connection ID is used for the duration of the connection, and it will be provided in the :c:member:`XTCP_NEW_CONNECTION` event,
so it can be matched with that ID supplied by the original call to :c:func:`socket`.

Due to the way TCP sockets work, a single listening socket can be used to accept multiple incoming connections.
Each time a new connection is `accepted`, the server will send an :c:member:`XTCP_ACCEPTED` event to the client with a **new** connection ID.
This ID is used in subsequent calls to send and receive data on the connection. So, the client should keep track of the connection IDs for each listening socket and each accepted connection.
Calling :c:func:`close` on a listening socket will close only the listening socket.

UDP connections
---------------

On a UDP socket, after calling :c:func:`connect` there is no `connection` event and the socket can be considered `connected` by the client and send and receive data as needed. Using the functions :c:func:`send` and :c:func:`recv`.
And respectively, after calling :c:func:`listen` there is no `accepted` event. However, the application simply waits for data to arrive on the socket with the :c:member:`XTCP_RECV_FROM_DATA` event. Then uses the functions :c:func:`recvfrom` and :c:func:`sendto` to receive and send data.

.. note:: From ``lib_xtcp`` v7.0.0, there is no need to call :c:func:`close` after receiving data from the UDP socket.
          This was required in previous versions of the library. Calling :c:func:`close` on a UDP socket will close the
          socket and it will need to be re-created with :c:func:`socket`.

A client could create a new UDP connection to port 15333 on a host at 192.168.0.2 using:

.. code-block:: C

  xtcp_ipaddr_t addr = { 192, 168, 0, 2 };
  int32_t id = i_xtcp.socket(XTCP_PROTOCOL_UDP);
  xtcp_error_code_t connect_result = i_xtcp.connect(id, 15333, addr);

Receiving Data
==============

When data is received for a client the server will indicate that there is a
packet ready and the :c:func:`get_event` call will indicate that the event
type is :c:member:`XTCP_RECV_DATA` or :c:member:`XTCP_RECV_FROM_DATA` and the packet data can be accessed by a call
to :c:func:`recv` or :c:func:`recvfrom` respectively.
For an indication of the sequence of events and calls please see :numref:`tcp_recv_sequence_section` and :numref:`udp_recv_sequence_section`.

Data is sent from the XTCP server to client as the UDP or TCP packets arrive
from the ethernet MAC. There is buffering in the server so new incoming packets
will be handled if there is sufficient memory.

On TCP connections there is a receive `window` that is used to manage the flow of
data. When the window is full the TCP protocol will delay further incoming packets until there is space available in the window.
The size of this window is determined by the maximum segment size (MSS), and the window is typically 4 times the MSS.
In the `standard` configuration the MSS is 1460 bytes, so the window size is typically 5840 bytes.
In the `minimal` configuration the MSS is 536 bytes, so the window size is typically 2144 bytes.

.. _tcp_recv_sequence_section:

.. uml::
  :caption: Example TCP/IP receive sequence
  :align: center
  :width: 50%

  CLIENT -> SERVER: i_xtcp.socket(XTCP_PROTOCOL_TCP)

  CLIENT -> SERVER: i_xtcp.listen()

  SERVER --> CLIENT: XTCP_ACCEPTED

  SERVER --> CLIENT: XTCP_RECV_DATA
  CLIENT -> SERVER: i_xtcp.recv(a)

  CLIENT -> SERVER: i_xtcp.send(1)
  SERVER --> CLIENT: XTCP_SENT_DATA
  
  SERVER --> CLIENT: XTCP_RECV_DATA
  CLIENT -> SERVER: i_xtcp.recv(b)

  CLIENT -> SERVER: i_xtcp.close()

On UDP connections there is no window, and packets are delivered to the client as they arrive.
If the remote host sends packets faster than the client can process them, then packets will be dropped.

.. _udp_recv_sequence_section:

.. uml::
  :caption: Example UDP receive sequence
  :align: center
  :width: 50%

  CLIENT -> SERVER: i_xtcp.socket(XTCP_PROTOCOL_UDP)

  CLIENT -> SERVER: i_xtcp.listen()

  SERVER --> CLIENT: XTCP_RECV_FROM_DATA
  CLIENT -> SERVER: i_xtcp.recvfrom(a)
  
  CLIENT -> SERVER: i_xtcp.sendto(1)
  
  SERVER --> CLIENT: XTCP_RECV_FROM_DATA
  CLIENT -> SERVER: i_xtcp.recvfrom(b)
  
  CLIENT -> SERVER: i_xtcp.close()

Sending Data
============

When sending data, the client is responsible for dividing the data
into chunks for the server and re-transmitting the previous chunk if a
transmission error occurs.
Generally, the client should send data in chunks no larger than the MSS for TCP connections, and MTU (1460 bytes) for UDP connections.

The client sends a packet by calling the :c:func:`send` interface function. 
On TCP connections a `resend` is done by calling :c:func:`send` function with the same data buffer as
the previous send.

After this data is sent to the server, two things can happen, shown in :numref:`tcp_send_sequence_fig`. 
Either, the server will respond with an :c:member:`XTCP_SENT_DATA` event, in
which case the next chunk of data can be sent. Or with an
:c:member:`XTCP_RESEND_DATA` event in which case the client must
re-transmit the previous chunk of data.

.. _tcp_send_sequence_fig:

.. uml::
  :caption: Example TCP/IP send sequence
  :align: center
  :width: 50%

  CLIENT -> SERVER: i_xtcp.socket(XTCP_PROTOCOL_TCP)

  CLIENT -> SERVER: i_xtcp.connect()
  SERVER --> CLIENT: XTCP_NEW_CONNECTION

  CLIENT -> SERVER: i_xtcp.send(1)
  SERVER --> CLIENT: XTCP_RESEND_DATA

  CLIENT -> SERVER: i_xtcp.send(1)
  SERVER --> CLIENT: XTCP_SENT_DATA
  
  SERVER --> CLIENT: XTCP_RECV_DATA
  CLIENT -> SERVER: i_xtcp.recv(a)

  CLIENT -> SERVER: i_xtcp.send(2)
  SERVER --> CLIENT: XTCP_SENT_DATA

  CLIENT -> SERVER: i_xtcp.close()

For UDP connections, there is no `sent` or `resend` events from the protocol, so the client can simply send data, see :numref:`udp_send_sequence_fig`, if no response is received in an appropriate amount of time then the data is lost and may be retried.
So, the client is responsible for any re-transmission of data if needed.

.. _udp_send_sequence_fig:

.. uml::
  :caption: Example UDP send sequence
  :align: center
  :width: 50%

  CLIENT -> SERVER: i_xtcp.socket(XTCP_PROTOCOL_UDP)

  CLIENT -> SERVER: i_xtcp.connect()

  CLIENT -> SERVER: i_xtcp.send(1)

  SERVER --> CLIENT: XTCP_RECV_DATA
  CLIENT -> SERVER: i_xtcp.recv(a)

  CLIENT -> SERVER: i_xtcp.send(2)
  
  CLIENT -> SERVER: i_xtcp.close()

When making UDP connections with :c:func:`connect` the client should use the
:c:func:`send` function to send data as the remote host address is already known.
When making UDP connections with :c:func:`listen` the client should use the
:c:func:`sendto` function to specify the remote host address. This address is typically supplied by the :c:func:`recvfrom` function.

Closing Connections
===================

When a client has finished with a connection it should call the
:c:func:`close` function with the connection ID. This will close the connection
and free any resources associated with it.

For TCP connections, if the remote host closes the connection then the client will
receive an :c:member:`XTCP_CLOSED` event and the client should then call
:c:func:`close` with the connection ID.

If the client needs to immediately shutdown the connection it should call the
:c:func:`abort` function with the connection ID. This will close the connection, sending a `reset` to the remote host if needed,
and free any resources associated with it.

If there is a problem with the connection then the client may receive a :c:member:`XTCP_TIMEOUT` event.
This currently happens if there is either a timeout waiting for a response from the remote host or
if the remote host resets the connection.

If the remote host aborts the connection or the LwIP stack has to recover from an error then the client will receive an
:c:member:`XTCP_ABORTED` event. The client does not need to call :c:func:`close`, as the resources should already be cleaned up. Thus, the client will likely receive events with an ID of -1.

Link Status Events
==================

As well as events related to connections, the server will also send
link status events to the client. The events :c:member:`XTCP_IFUP` and
:c:member:`XTCP_IFDOWN` indicate to a client when the link goes up or down.

The connection ID should be ignored for these events, as the event relates to the network interface and not a connection.

When the link goes down all existing TCP data connections will be closed by the server, and the client should clean up as needed. Listening sockets may be left open, but any active connections will be closed.

Server Configuration
====================

The server is configured via arguments passed to server task, see section 
:ref:`xtcp_server_api` (:c:func:`xtcp_lwip`) and the defines 
described in section :ref:`sec_config_defines`.

.. note:: The ``lib_xtcp`` will only build against `real-time` MACs, due to the
   use of ``lib_ethernet`` timestamps in the TCP/IP stack.

XTCP Configuration
==================

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

``lib_xtcp`` is intended to be used with the `XCommon CMake <https://www.xmos.com/file/xcommon-cmake-documentation/?version=latest>`_
, the `XMOS` application build and dependency management system.

To use this library, include ``lib_xtcp`` in the application's
``APP_DEPENDENT_MODULES`` list in `CMakeLists.txt`, for example:

.. code-block:: cmake

  set(APP_DEPENDENT_MODULES "lib_xtcp")

All functions and types can be found in the ``xtcp.h`` header file:

.. code-block:: C

  #include <xtcp.h>

.. _getting_Started_section:

Example Application
===================

The app_simple_webserver example is provided to show how the library can 
use TCP traffic for a very simple HTTP server.

The example targets the ``XK-ETH-316-DUAL`` dev-kit and 100BASE-T ethernet 
with an RMII PHY.

For an example of using ``lib_xtcp`` on the ``XCORE-200`` with Gigabit Ethernet,
say the ``XCORE-200-EXPLORER`` dev-kit, see the example application note ``AN02044``.

The ``lib_xtcp`` uses a third-party TCP/IP stack, the ``LwIP`` stack. This is built automatically
when the library is built. ``lib_xtcp`` uses one thread to run the TCP/IP stack and uses around 50 kB of code
and 40 kB of data, and the application client runs in another thread. The memory usage will vary
depending on the configuration of the stack and the application.

By default the IP address for the xcore will be a static IP address, please update the IPv4 
address to match your network, in the first row of ``ipconfig`` and the subnet mask to the second 
row, the subnet mask is typically ``{ 255, 255, 255, 0 }``. Otherwise, to set the IP address
automatically assigned via DHCP, fill :c:struct:`xtcp_ipconfig_t` ``ipconfig = { ... };`` in ``main.xc``
with zeros. For details please see section :ref:`ip_configuration_section`

The excerpt from the example web server shown below shows how to configure the 
``lib_xtcp`` server with the application client here as `xhttpd`

.. literalinclude:: ../../examples/app_simple_webserver/src/main.xc
   :language: C
   :start-at: int main(void)

The function :c:func:`xhttpd`, called from main will listen for a TCP connection
on port 80 and shows an example of handling the events and data flowing to and 
from the TCP stack. For details please see section 
:ref:`events_and_connections_section` and the notifications are defined in 
:ref:`lib_xtcp_event_types`.

.. literalinclude:: ../../examples/app_simple_webserver/src/httpd.xc
   :language: C
   :start-at: void xhttpd
   :end-at: httpd_init_state

Building the example
====================

This section assumes that the `XMOS XTC Tools <https://www.xmos.com/software-tools/>`_ have been
downloaded and installed. The required version is specified in the accompanying ``README``.

Installation instructions can be found `here <https://wwww.xmos.com/xtc-install-guide>`_.

Special attention should be paid to the section on
`Installation of Required Third-Party Tools <https://www.xmos.com/documentation/XM-014363-PC/html/installation/install-configure/install-tools/install_prerequisites.html>`_.

The application is built using the `xcommon-cmake <https://www.xmos.com/file/xcommon-cmake-documentation/?version=latest>`_
build system, which is provided with the XTC tools and is based on `CMake <https://cmake.org/>`_.

The ``lib_xtcp`` software ZIP package should be downloaded and extracted to a chosen working
directory.

To configure the build, the following commands should be run from an XTC command prompt:

.. code-block:: shell

  cd lib_xtcp
  cd examples/app_simple_webserver

  cmake -B build -G "Unix Makefiles"
  
  xmake -j -C build

Once built run with,

.. code-block:: shell

  xrun --xscope bin/app_simple_webserver.xe

Alternatively, the application can be programmed into flash memory for standalone execution:

.. code-block:: shell

   xflash bin/app_simple_webserver.xe

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

Configuration defines can either be overridden by adding the file
``xtcp_conf.h`` into the application and then putting
``#define`` directives into that header file (which will then be read
by the library on build).

.. doxygendefine:: XTCP_HOSTNAME

.. doxygendefine:: MAX_XTCP_CLIENTS

.. doxygendefine:: CLIENT_QUEUE_SIZE

LwIP Configuration
------------------

There are 2 predefined ``lwipopts.h`` header files provided with the library,
`standard` and `minimal`, which indicates the memory resource usage of each.
The `standard` configuration is the default and provides better performance by having a larger memory footprint.
To override the default configuration add the CMake define to the project:

.. code-block:: cmake

   set(LWIP_OPTS_PATH <relative-path-to-lwipopts.h>)

Path is relative to the ``lib_xtcp/lib_xtcp`` folder path not the client application.
So, the path may need to start with ``../../<lwipopts-h-path>`` to go up one or more folders.

Client Callback Function
========================

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

.. doxygenstruct:: xtcp_host_t

.. doxygenstruct:: xtcp_ipconfig_t

.. doxygenenum:: xtcp_protocol_t

.. doxygenenum:: xtcp_error_code_t

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
