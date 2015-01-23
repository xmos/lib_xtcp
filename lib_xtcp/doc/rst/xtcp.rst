.. include:: ../../../README.rst

Typical Resource Usage
......................

.. resusage::

  * - configuration: Standard
    - globals: xtcp_ipconfig_t ipconfig = {
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 },
               { 0, 0, 0, 0 }
               };
    - locals: interface mii_if i_mii; chan c_xtcp[1];
    - fn: xtcp(c_xtcp, 1, i_mii,
               null, null, null,
               null, null, null, ipconfig);
    - pins: 0
    - ports: 0


Software version and dependencies
.................................

.. libdeps::

Related application notes
.........................

TODO

Usage
-----

The TCP/IP stack runs in a task implemented in the :c:func:`xtcp`
function. This task connects to either the MII component in the
Ethernet library or one of the MAC components in the Ethernet library.
See the Ethernet library user guide for details on these components.

.. figure:: images/xtcp_task_diag.*

   XTCP task diagram

Clients can interact with the TCP/IP stack via xC channels connected
to the component using the client functions described in
:ref:`xtcp_client_api`.

If your application has no need of direct layer 2 traffic to the
Ethernet MAC then the most resource efficient approach is to connect
the ``xtcp`` component directly to the MII layer component.

IP Configuration
................

The server will determine its IP configuration based on the arguments
passed into the :c:func:`xtcp` function.
If an address is supplied then that address will be used (a static IP address
configuration).

If no address is supplied then the server will first
try to find a DHCP server on the network to obtain an address
automatically. If it cannot obtain an address from DHCP, it will determine
a link local address (in the range 169.254/16) automatically using the
Zeroconf IPV4LL protocol.

To use dynamic address, the :c:func:`xtcp` function can be passed a
structure with an IP address that is all zeros.

Events and Connections
......................

The TCP/IP stack client interface is a low-level event based
interface. This is to allow applications to manage buffering and
connection management in the most efficient way possible for the
application. 

.. only:: html

  .. figure:: images/events-crop.png
     :align: center

     Example event sequence

.. only:: latex

  .. figure:: images/events-crop.pdf
     :figwidth: 50%
     :align: center

     Example event sequence


Each client will receive *events* from the server. These events
usually have an associated *connection*. In addition to receiving
these events the client can send *commands* to the server to initiate
new connections and so on.

The above Figure shows an example event/command sequence of a
client making a connection, sending some data, receiving some data and
then closing the connection. Note that sending and receiving may be
split into several events/commands since the server itself performs no
buffering. 

If the client is handling multiple connections then the server may
interleave events for each connection so the client has to hold a
persistent state for each connection.

The connection and event model is the same from both TCP connections
and UDP connections. Full details of both the possible events and
possible commands can be found in Section :ref:`sec_api`.

TCP and UDP
...........

The XTCP API treats UDP and TCP connections in the same way. The only
difference is when the protocol is specified on initializing
connections with :c:func:`xtcp_connect` or :c:func:`xtcp_listen`.

New Connections
...............

New connections are made in two different ways. Either the
:c:func:`xtcp_connect` function is used to initiate a connection with
a remote host as a client or the :c:func:`xtcp_listen` function is
used to listen on a port for other hosts to connect to the application
. In either
case once a connection is established then the
:c:member:`XTCP_NEW_CONNECTION` event is triggered.

In the Berkley sockets API, a listening UDP connection merely reports
data received on the socket, indepedent of the source IP address.  In
XTCP, a :c:member:`XTCP_NEW_CONNECTION` event is sent each time data
arrives from a new source.  The API function :c:func:`xtcp_close`
should be called after the connection is no longer needed.

Receiving Data
..............

When data is received by a connection, the :c:member:`XTCP_RECV_DATA`
event is triggered and communicated to the client. At this point the
client **must** call the :c:func:`xtcp_recv` function to receive the
data. 

Data is sent from host to client as the UDP or TCP packets come
in. There is no buffering in the server so it will wait for the client
to handle the event before processing new incoming packets.

Sending Data
............

When sending data, the client is responsible for dividing the data
into chunks for the server and re-transmitting the previous chunk if a
transmission error occurs. 

.. note:: Note that re-transmission may be needed on
          both TCP and UDP connections. On UDP connections, the
          transmission may fail if the server has not yet established
          a connection between the destination IP address and layer 2
          MAC address.
          
The client can initiate a send transaction with the
:c:func:`xtcp_init_send` function. At this point no sending has been
done but the server is notified of a wish to send. The client must
then wait for a :c:member:`XTCP_REQUEST_DATA` event at which point it
must respond with a call to :c:func:`xtcp_send`. 

.. note:: The maximum buffer size that can be sent in one call to 
          `xtcp_send` is contained in the `mss`
          field of the connection structure relating to the event.

After this data is sent to the server, two things can happen: Either
the server will respond with an :c:member:`XTCP_SENT_DATA` event, in
which case the next chunk of data can be sent or with an
:c:member:`XTCP_RESEND_DATA` event in which case the client must
re-transmit the previous chunk of data. 

The command/event exchange continues until the client calls the
:c:func:`xtcp_complete_send` function to finish the send
transaction. After this the server will not trigger any more
:c:member:`XTCP_SENT_DATA` events.

Link Status Events
..................

As well as events related to connections. The server may also send
link status events to the client. The events :c:member:`XTCP_IFUP` and 
:c:member:`XTCP_IFDOWN` indicate to a client when the link goes up or down.

Configuration
.............

The server is configured via arguments passed to the
:c:func:`xtcp_server` function and the defines described in Section
:ref:`sec_config_defines`.

Client connections are configured via the client API described in
Section :ref:`sec_config_defines`.


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

``XTCP_EXCLUDE_LISTEN``
       Exclude support for the listen command from the server,
       reducing memory footprint.

``XTCP_EXCLUDE_UNLISTEN``
       Exclude support for the unlisten command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_CONNECT``
       Exclude support for the connect command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_BIND_REMOTE``
       Exclude support for the bind_remote command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_BIND_LOCAL``
       Exclude support for the bind_local command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_INIT_SEND``
       Exclude support for the init_send command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_SET_APPSTATE``
       Exclude support for the set_appstate command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_ABORT``
       Exclude support for the abort command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_CLOSE``
       Exclude support for the close command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_SET_POLL_INTERVAL``
       Exclude support for the set_poll_interval command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_JOIN_GROUP``
       Exclude support for the join_group command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_LEAVE_GROUP``
       Exclude support for the leave_group command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_GET_MAC_ADDRESS``
       Exclude support for the get_mac_address command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_GET_IPCONFIG``
       Exclude support for the get_ipconfig command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_ACK_RECV``
       Exclude support for the ack_recv command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_ACK_RECV_MODE``
       Exclude support for the ack_recv_mode command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_PAUSE``
       Exclude support for the pause command from the server,
       reducing memory footprint

``XTCP_EXCLUDE_UNPAUSE``
       Exclude support for the unpause command from the server,
       reducing memory footprint

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

Functional API
--------------

Data Structures/Types
.....................

.. doxygentypedef:: xtcp_ipaddr_t

.. doxygenstruct:: xtcp_ipconfig_t

.. doxygenenum:: xtcp_protocol_t

|newpage|

.. doxygenenum:: xtcp_event_type_t

.. doxygenenum:: xtcp_connection_type_t

.. doxygenstruct:: xtcp_connection_t

|newpage|

Server API
..........

.. doxygenfunction:: xtcp

.. _xtcp_client_api:

|newpage|

Client API
..........

Event Receipt
+++++++++++++

.. doxygenfunction:: xtcp_event

Setting Up Connections
++++++++++++++++++++++

.. doxygenfunction:: xtcp_listen
.. doxygenfunction:: xtcp_unlisten
.. doxygenfunction:: xtcp_connect
.. doxygenfunction:: xtcp_bind_local
.. doxygenfunction:: xtcp_bind_remote
.. doxygenfunction:: xtcp_set_connection_appstate

Receiving Data
++++++++++++++

.. doxygenfunction:: xtcp_recv
.. doxygenfunction:: xtcp_recvi
.. doxygenfunction:: xtcp_recv_count

Sending Data
++++++++++++

.. doxygenfunction:: xtcp_init_send
.. doxygenfunction:: xtcp_send
.. doxygenfunction:: xtcp_sendi
.. doxygenfunction:: xtcp_complete_send

Other Connection Management
+++++++++++++++++++++++++++

.. doxygenfunction:: xtcp_set_poll_interval

.. doxygenfunction:: xtcp_close
.. doxygenfunction:: xtcp_abort

.. doxygenfunction:: xtcp_pause
.. doxygenfunction:: xtcp_unpause

Other General Client Functions
++++++++++++++++++++++++++++++

.. doxygenfunction:: xtcp_join_multicast_group
.. doxygenfunction:: xtcp_leave_multicast_group
.. doxygenfunction:: xtcp_get_mac_address
.. doxygenfunction:: xtcp_get_ipconfig

|newpage|

|appendix|

Known Issues
------------

There are no known issues with this library.

.. include:: ../../../CHANGELOG.rst
