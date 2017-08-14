.. include:: ../../../README.rst


Usage
-----

The TCP/IP stack runs in a task implemented in either the :c:func:`xtcp_uip` or
:c:func:`xtcp_lwip` functions depending on which stack implementation you wish
to use. The interfaces to the stack are the same, regardless of which
implementation is being used.

This task connects to either the MII component in the Ethernet library or one
of the MAC components in the Ethernet library.
See the Ethernet library user guide for details on these components.

.. figure:: images/xtcp_task_diag.*

   XTCP task diagram

Clients can interact with the TCP/IP stack via interfaces connected
to the component using the interface functions described in
:ref:`xtcp_client_api`.

If your application has no need of direct layer 2 traffic to the
Ethernet MAC then the most resource efficient approach is to connect
the ``xtcp`` component directly to the MII layer component.

IP Configuration
................

The server will determine its IP configuration based on the ``xtcp_ipconfig_t``
configuration passed into the :c:func:`xtcp_uip` / :c:func:`xtcp_lwip` task.
If an address is supplied then that address will be used (a static IP address
configuration)::

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

To use dynamic address, the :c:func:`xtcp_uip` and :c:func:`xtcp_lwip`
functions can be passed a structure with an IP address that is all zeros::

  xtcp_ipconfig_t ipconfig = {
    { 0, 0, 0, 0 }, // ip address
    { 0, 0, 0, 0 }, // netmask
    { 0, 0, 0, 0 }  // gateway
  };

Events and Connections
......................

The TCP/IP stack client interface is a Berkley-like interface.

Each client will receive packet ready *events* from the server to indicate that
the server has new data for that client. The client then collects the packet
using the :c:func:`recv` call.

The packets sent from the server can be either data or control packets. The type
of packet is indicated in the connection state :c:member:`event` member. The
possible packet types are defined in :ref:`lib_xtcp_event_types`.

A client will typically handle its connection to the XTCP server in the following
manner::

  xtcp_connection_t conn = i_xtcp.socket(...);
  ...
  select {
    case i_xtcp.event_ready():
      // Handle event
      switch (i_xtcp.get_event(conn)) {
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
...............

New connections are made in two different ways. Either the
:c:func:`connect` function is used to initiate a connection with
a remote host as a client or the :c:func:`listen` function is
used to listen on a port for other hosts to connect to the application.
In either case once a connection is established then the
:c:member:`XTCP_NEW_CONNECTION` event is received by the client.

In the Berkley sockets API, a listening UDP connection merely reports
data received on the socket, indepedent of the source IP address.  In
XTCP, a :c:member:`XTCP_NEW_CONNECTION` event is sent each time data
arrives from a new source.  The API function :c:func:`close`
should be called after the connection is no longer needed.

TCP and UDP
...........

The XTCP API treats UDP and TCP connections in the same way. The only
difference is when the protocol is specified on initializing
connections with the interface :c:func:`connect`, :c:func:`socket` or :c:func:`listen`
functions. Note that the protocol given in :c:func:`socket` must match the protocol
given in the corresponding call to :c:func:`connect` or :c:func:`listen`.

For example, an HTTP client would listen for TCP connections on port 80::

  xtcp_connection_t conn = i_xtcp.socket(XTCP_PROTOCOL_TCP);
  i_xtcp.listen(conn, 80, XTCP_PROTOCOL_TCP);

A client could create a new UDP connection to port 15333 on a machine at
192.168.0.2 using::

  xtcp_ipaddr_t addr = { 192, 168, 0, 2 };
  xtcp_connection_t conn = i_xtcp.socket(XTCP_PROTOCOL_UDP);
  i_xtcp.connect(conn, 15333, addr, XTCP_PROTOCOL_UDP);

Receiving Data
..............

When data is received for a client the server will indicate that there is a
packet ready and the :c:func:`get_event` call will indicate that the event
type is :c:member:`XTCP_RECV_DATA`. This will gaurantee that data is available
to read with a :c:func:`recv` call on the associated :c:member:`xtcp_connection_t`.

Sending Data
............

.. note:: Note that re-transmission may be needed on
          both TCP and UDP connections. On UDP connections, the
          transmission may fail if the server has not yet established
          a connection between the destination IP address and layer 2
          MAC address.

The client sends a packet by calling the :c:func:`send` interface function.

.. note:: The maximum buffer size that can be sent in one call to
          `xtcp_send` is contained in the `mss` field of the connection
          structure relating to the event.

  .. figure:: images/events.*
     :width: 50%

     Example send sequence

Closed Connection
.................

In the event that the connection is disconnected by the remote host on a TCP socket,
a :c:member:`XTCP_CLOSED` event is raised.

Link Status Events
..................

As well as events related to connections. The server may also send
link status events to the client. The events :c:member:`XTCP_IFUP` and
:c:member:`XTCP_IFDOWN` indicate to a client when the link goes up or down.

Configuration
.............

The server is configured via arguments passed to server task (:c:func:`xtcp_uip`/
:c:func:`xtcp_lwip`) and the defines described in Section :ref:`sec_config_defines`.

Configuration API
-----------------

.. _sec_config_defines:

Configuration Defines
.....................

Configuration defines can either be set by adding the a command line
option to the build flags in your application Makefile
(i.e. ``-DDEFINE=VALUE``) or by adding the file
``xtcp_client_conf.h`` into your application and then putting
``#define`` directives into that header file (which will then be read
by the library on build).

``XTCP_CLIENT_BUF_SIZE``
       The buffer size used for incoming packets. This has a maximum
       value of 1472 which can handle any incoming packet. If it is
       set to a smaller value, larger incoming packets will be truncated. Default
       is 1472.

``UIP_CONF_MAX_CONNECTIONS``
       The maximum number of UDP or TCP connections the server can
       handle simultaneously. Default is 20.

``UIP_CONF_MAX_LISTENPORTS``
       The maximum number of UDP or TCP ports the server can listen to
       simultaneously. Default is 20.

``UIP_USE_AUTOIP``
       By defining this as 0, the IPv4LL application is removed from the code. Do this to save
       approxmiately 1kB.  Auto IP is a stateless protocol that assigns an IP address to a
       device.  Typically, if a unit is trying to use DHCP to obtain an address, and a server
       cannot be found, then auto IP is used to assign an address of
       the form 169.254.x.y. Auto IP is enabled by default

``UIP_USE_DHCP``
       By defining this as 0, the DHCP client is removed from the
       code. This will save approximately 2kB.
       DHCP is a protocol for dynamically acquiring an IP address from
       a centralised DHCP server.  This option is enabled by default.

.. _lib_xtcp_api:

Functional API
--------------

All functions can be found in the ``xtcp.h`` header file::

  #include <xtcp.h>

The application also needs to add ``lib_xtcp`` to its build modules::

  USED_MODULES = ... lib_xtcp ...

Data Structures/Types
.....................

.. doxygentypedef:: xtcp_ipaddr_t

.. doxygenstruct:: xtcp_ipconfig_t

.. doxygenenum:: xtcp_protocol_t

|newpage|

.. _lib_xtcp_event_types:

.. doxygenenum:: xtcp_event_type_t

.. doxygenstruct:: xtcp_connection_t

|newpage|

Server API
..........

.. doxygenfunction:: xtcp_uip

.. doxygenfunction:: xtcp_lwip

|newpage|

.. _xtcp_client_api:

Client API
..........

.. doxygeninterface:: xtcp_if

|newpage|

|appendix|

Known Issues
------------

The library does not support IPv6.

.. include:: ../../../CHANGELOG.rst
