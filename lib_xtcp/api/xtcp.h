// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved
#ifndef __xtcp_h__
#define __xtcp_h__

#include <mii.h>
#include <smi.h>
#include <ethernet.h>
#include <otp_board_info.h>
#include <xccompat.h>

#ifndef XTCP_CLIENT_BUF_SIZE
#define XTCP_CLIENT_BUF_SIZE (1472)
#endif
#ifndef XTCP_MAX_RECEIVE_SIZE
#ifdef UIP_CONF_RECEIVE_WINDOW
#define XTCP_MAX_RECEIVE_SIZE (UIP_CONF_RECEIVE_WINDOW)
#else
#define XTCP_MAX_RECEIVE_SIZE (1472)
#endif
#endif

/** Used by the LWIP and uIP callback functions to
 *  correctly pass packets to the DHCP functions 
 */
#define DHCPC_SERVER_PORT  67
#define DHCPC_CLIENT_PORT  68

/** Maximum number of listening ports for XTCP */
#define NUM_TCP_LISTENERS 20
#define NUM_UDP_LISTENERS 20

/** Please note that IPv6 is not officially supported and use of this
 *   define should be considered experimental at the user's own risk
 */
#if IPV6
#define UIP_CONF_IPV6 1
#else
#define UIP_CONF_IPV6 0
#endif

typedef unsigned int xtcp_appstate_t;

#if UIP_CONF_IPV6
/** XTCP IP address.
 *
 *  This data type represents a single ipv6 address in the XTCP
 *  stack.
 */
typedef union xtcp_ip6addr_t {
  unsigned char  u8[16];			/* Initialiser, must come first. */
  unsigned short u16[8];
} xtcp_ip6addr_t;

typedef xtcp_ip6addr_t xtcp_ipaddr_t;

#else /* UIP_CONF_IPV6 -> UIP_CONF_IPV4 */

/** XTCP IP address.
 *
 *  This data type represents a single ipv4 address in the XTCP
 *  stack.
 */
typedef unsigned char xtcp_ipaddr_t[4];

#endif /* UIP_CONF_IPV6 */

/** IP configuration information structure.
 *
 *  This structure describes IP configuration for an ip node.
 *
 **/
#if UIP_CONF_IPV6
typedef struct xtcp_ipconfig_t {
  int v;		               /**< used ip protocol version */
  xtcp_ipaddr_t ipaddr;    /**< The IP Address of the node */
} xtcp_ipconfig_t;
#else
typedef struct xtcp_ipconfig_t {
  xtcp_ipaddr_t ipaddr;    /**< The IP Address of the node */
  xtcp_ipaddr_t netmask;   /**< The netmask of the node. The mask used
                                to determine which address are routed locally.*/
  xtcp_ipaddr_t gateway;   /**< The gateway of the node */
} xtcp_ipconfig_t;
#endif

/** XTCP protocol type.
 *
 * This determines what type a connection is: either UDP or TCP.
 *
 **/
typedef enum xtcp_protocol_t {
  XTCP_PROTOCOL_TCP, /**< Transmission Control Protocol */
  XTCP_PROTOCOL_UDP  /**< User Datagram Protocol */
} xtcp_protocol_t;


/** XTCP event type.
 *
 *  The event type represents what event is occuring on a particular connection.
 *  It is instantiated as part of the xtcp_connection_t structure in the function
 *  get_packet().
 *
 **/
typedef enum xtcp_event_type_t {
  XTCP_NEW_CONNECTION,  /**<  This event represents a new connection has been
                              made. In the case of a TCP server connections it
                              occurs when a remote host firsts makes contact
                              with the local host. For TCP client connections
                              it occurs when a stream is setup with the remote
                              host.
                              For UDP connections it occurs as soon as the
                              connection is created. **/

  XTCP_RECV_DATA,       /**<  This event occurs when the connection has received
                              some data. The return_len in get_packet() will 
                              indicate the length of the data. The data will be
                              present in the buffer passed to get_packet(). **/

  XTCP_SENT_DATA,       /**<  This event occurs when the server has successfully
                              sent the previous piece of data that was given
                              to it via a call to send(). **/

  XTCP_RESEND_DATA,     /**<  This event occurs when the server has failed to
                              send the previous piece of data that was given
                              to it via a call to send(). The server
                              is now requesting for the same data to be sent
                              again. **/

  XTCP_TIMED_OUT,      /**<   This event occurs when the connection has
                              timed out with the remote host (TCP only).
                              This event represents the closing of a connection
                              and is the last event that will occur on
                              an active connection. */

  XTCP_ABORTED,        /**<   This event occurs when the connection has
                              been aborted by the local or remote host
                              (TCP only).
                              This event represents the closing of a connection
                              and is the last event that will occur on
                              an active connection. */

  XTCP_CLOSED,         /**<   This event occurs when the connection has
                              been closed by the local or remote host.
                              This event represents the closing of a connection
                              and is the last event that will occur on
                              an active connection. */

  XTCP_IFUP,           /**<   This event occurs when the link goes up (with
                              valid new ip address). This event has no
                              associated connection. */

  XTCP_IFDOWN,         /**<   This event occurs when the link goes down.
                              This event has no associated connection. */

  XTCP_DNS_RESULT      /**<   This event occurs when the XTCP connection has a DNS
                              result for a request. **/
} xtcp_event_type_t;

/** Type representing a connection type.
 *
 */
typedef enum xtcp_connection_type_t {
  XTCP_CLIENT_CONNECTION,  /**< A client connection */
  XTCP_SERVER_CONNECTION   /**< A server connection */
} xtcp_connection_type_t;


/** This type represents a TCP or UDP connection.
 *
 *  This is the main type containing connection information for the client
 *  to handle. Elements of this type are instantiated by the xtcp_event()
 *  function which informs the client about an event and the connection
 *  the event is on.
 *
 **/
typedef struct xtcp_connection_t {
  int client_num;             /**< The number of the client connected */
  int id;                     /**< A unique identifier for the connection */
  xtcp_protocol_t protocol;   /**< The protocol of the connection (TCP/UDP) */
  xtcp_connection_type_t connection_type; /**< The type of connection (client/sever) */
  xtcp_event_type_t event;    /**< The last reported event on this connection. */
  xtcp_appstate_t appstate;   /**< The application state associated with the
                                   connection. This is set using the
                                   set_appstate() function. */
  xtcp_ipaddr_t remote_addr;  /**< The remote ip address of the connection. */
  unsigned int remote_port;   /**< The remote port of the connection. */
  unsigned int local_port;    /**< The local port of the connection. */
  unsigned int mss;           /**< The maximum size in bytes that can be send using
                                   xtcp_send() after a send event */
  unsigned packet_length;
  int uip_conn;               /**< Pointer to the associated uIP connection. 
                                   Only to be used by XTCP */
#ifdef XTCP_ENABLE_PARTIAL_PACKET_ACK
  unsigned int outstanding;   /**< The amount left inflight after a partial packet has been acked */
#endif
} xtcp_connection_t;


/** \brief Convert a unsigned integer representation of an ip address into
 *         the xtcp_ipaddr_t type.
 *
 * \param ipaddr The result ipaddr
 * \param i      An 32-bit integer containing the ip address (network order)
 * \note         Not available for IPv6
 */
void xtcp_uint_to_ipaddr(xtcp_ipaddr_t ipaddr, unsigned int i);

/** \brief Set a connection into ack-receive mode.
 *
 *  In ack-receive mode after a receive event the tcp window will be set to
 *  zero for the connection (i.e. no more data will be received from the other end).
 *  This will continue until the client calls the xtcp_ack_recv functions.
 *
 * \param c_xtcp      chanend connected to the xtcp server
 * \param conn        the connection
 */
void xtcp_ack_recv_mode(chanend c_xtcp,
                        REFERENCE_PARAM(xtcp_connection_t,conn)) ;


/** \brief Ack a receive event
 *
 * In ack-receive mode this command will acknowledge the last receive and
 * therefore
 * open the receive window again so new receive events can occur.
 *
 * \param c_xtcp      chanend connected to the xtcp server
 * \param conn        the connection
 **/
void xtcp_ack_recv(chanend c_xtcp,
                   REFERENCE_PARAM(xtcp_connection_t,conn));

/** \brief Get the current host MAC address of the server.
 *
 * \param c_xtcp      chanend connected to the xtcp server
 * \param mac_addr    the array to be filled with the mac address
 **/
void xtcp_get_mac_address(chanend c_xtcp, unsigned char mac_addr[]);

/** \brief Get the IP config information into a local structure
 *
 * Get the current host IP configuration of the server.
 *
 * \param c_xtcp      chanend connected to the xtcp server
 * \param ipconfig    the structure to be filled with the IP configuration
 *                    information
 **/
void xtcp_get_ipconfig(chanend c_xtcp,
                       REFERENCE_PARAM(xtcp_ipconfig_t, ipconfig));


/** \brief pause a connection.
 *
 *  No further reads and writes will occur on the network.
 *  \param c_xtcp	chanend connected to the xtcp server
 *  \param conn		tcp connection structure
 *  \note         This functionality is considered experimental for when using IPv6.
 */
void xtcp_pause(chanend c_xtcp,
                REFERENCE_PARAM(xtcp_connection_t,conn));


/** \brief unpause a connection
 *
 *  Activity is resumed on a connection.
 *
 *  \param c_xtcp	chanend connected to the xtcp server
 *  \param conn		tcp connection structure
 *  \note         This functionality is considered experimental for when using IPv6.
 */
void xtcp_unpause(chanend c_xtcp,
                  REFERENCE_PARAM(xtcp_connection_t,conn));


/** \brief Enable a connection to accept acknowledgements of partial packets that have been sent.
 *
 *  \param c_xtcp	chanend connected to the xtcp server
 *  \param conn		tcp connection structure
 *  \note         This functionality is considered experimental for when using IPv6.
 */
void xtcp_accept_partial_ack(chanend c_xtcp,
                             REFERENCE_PARAM(xtcp_connection_t,conn));

#ifdef __XC__
typedef interface xtcp_if {
    /** \brief Recieve information/data from the XTCP server.
   *
   *  After this call, when a connection is established an
   *  XTCP_NEW_CONNECTION event is signalled.
   *
   * \param &conn       The connection to be passed in that will 
   *                    contain all the connection information.
   * \param data        An array where XTCP server can write data to.
   * \param length      An integer where the server can indicate
   *                    the length of the sent packet.
   */
  [[clears_notification]] void get_packet(xtcp_connection_t &conn, char data[n], unsigned int n, unsigned &length);

  /** \brief Notifies the client that there is data/information
   *         ready for them.
   *
   *  After this notification is raised a call to get_packet()
   *  is needed.
   */
  [[notification]] slave void packet_ready();
  
  /** \brief Listen to a particular incoming port.
   *
   *  After this call, when a connection is established an
   *  XTCP_NEW_CONNECTION event is signalled.
   *
   * \param port_number The local port number to listen to
   * \param protocol    The protocol to listen to (TCP or UDP)
   */
  void listen(int port_number, xtcp_protocol_t protocol);
  
  /** \brief Stop listening to a particular incoming port.
   *
   * \param port_number local port number to stop listening on
   */
  void unlisten(unsigned port_number);

  /** \brief Close a connection.
   *
   *  May still recieve data on a TCP connection. Use abort() if
   *  you wish to completely stop all data. Will continue to listen
   *  on the open port the connection came from.
   *
   * \param conn        the connection
   */
  void close(xtcp_connection_t conn);

  /** \brief Abort a connection.
   *
   *  For UDP this is the same as closing the connection. For TCP
   *  the server will send a RST signal and stop all incoming data.
   *
   * \param conn        the connection
   */
  void abort(xtcp_connection_t conn);

  /** \brief Try to connect to a remote port.
   *
   *  For TCP this will initiate the three way handshake.
   *  For UDP this will assign a random local port and bind the remote
   *  end of the connection to the host specified.
   *
   * \param port_number The remote port to try to connect to
   * \param ipaddr      The ip addr of the remote host
   * \param protocol    The protocol to connect with (TCP or UDP)
   */
  void connect(unsigned port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol);

  /** \brief Send data to the connection.
   *
   * \param conn        The connection
   * \param data        An array of data to send
   * \param len         The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   */
  void send(xtcp_connection_t conn, char data[], unsigned len);

  /** \brief Send data to the connection.
   *
   *  The data is sent starting from the index i.e. data[i] is the first
   *  byte to be sent.
   *
   * \param conn        The connection.
   * \param data        An array of data to send.
   * \param index       The index at which to start reading from the data array.
   * \param len         The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   */
  void send_with_index(xtcp_connection_t conn, char data[], unsigned index, unsigned len);

  /** \brief Subscribe to a particular IP multicast group address.
   *
   * \param addr        The address of the multicast group to join. It is
   *                    assumed that this is a multicast IP address.
   * \note              Not available for IPv6
   */
  void join_multicast_group(xtcp_ipaddr_t addr);

  /** \brief Unsubscribe from a particular IP multicast group address.
   *
   * \param addr        The address of the multicast group to leave. It is
   *                    assumed that this is a multicast IP address.
   * \note              Not available for IPv6
   */
  void leave_multicast_group(xtcp_ipaddr_t addr);

  /** \brief Set the connections application state data item
   *
   * After this call, subsequent events on this connection
   * will have the appstate field of the connection set.
   *
   * \param conn        The connection
   * \param appstate    An unsigned integer representing the state. In C
   *                    this is usually a pointer to some connection dependent
   *                    information.
   */
  void set_appstate(xtcp_connection_t conn, xtcp_appstate_t appstate);

  /** \brief Bind the local end of a connection to a particular port (UDP).
   *
   * \param conn        The connection
   * \param port_number The local port to set the connection to.
   */
  void bind_local_udp(xtcp_connection_t conn, unsigned port_number);

  /** \brief Bind the remote end of a connection to a particular port and
   *         ip address (UDP).
   *
   * After this call, packets sent to this connection will go to
   * the specified address and port
   *
   * \param conn        The connection
   * \param addr        The intended remote address of the connection
   * \param port_number The intended remote port of the connection
   */
  void bind_remote_udp(xtcp_connection_t conn, xtcp_ipaddr_t ipaddr, unsigned port_number);
  
  /** \brief 
   *
   *
   * \param hostname    The human readable host name, e.g. "www.xmos.com"     
   * \note              LWIP ONLY.
   */
  void request_host_by_name(const char hostname[]);
} xtcp_if;

/** Function implementing the TCP/IP stack task.
 *
 *  This functions implements a TCP/IP stack that clients can access via
 *  interfaces.
 *
 *  \param i_xtcp_init  The interface array to connect to the clients.
 *  \param n_xtcp_init  The number of clients to the task.
 *  \param i_mii        If this component is connected to the mii() component
 *                      in the Ethernet library then this interface should be
 *                      used to connect to it. Otherwise it should be set to
 *                      null
 *  \param i_eth_cfg    If this component is connected to an MAC component
 *                      in the Ethernet library then this interface should be
 *                      used to connect to it. Otherwise it should be set to
 *                      null.
 *  \param i_eth_rx     If this component is connected to an MAC component
 *                      in the Ethernet library then this interface should be
 *                      used to connect to it. Otherwise it should be set to
 *                      null.
 *  \param i_eth_tx     If this component is connected to an MAC component
 *                      in the Ethernet library then this interface should be
 *                      used to connect to it. Otherwise it should be set to
 *                      null.
 *  \param i_smi        If this connection to an Ethernet SMI component is
 *                      then the XTCP component will poll the Ethernet PHY
 *                      for link up/link down events. Otherwise, it will
 *                      expect link up/link down events from the connected
 *                      Ethernet MAC.
 *  \param phy_address  The SMI address of the Ethernet PHY
 *  \param mac_address  If this array is non-null then it will be used to set
 *                      the MAC address of the component.
 *  \param otp_ports    If this port structure is non-null then the component
 *                      will obtain the MAC address from OTP ROM. See the OTP
 *                      reading library user guide for details.
 *  \param ipconfig     This :c:type:`xtcp_ipconfig_t` structure is used
 *                      to determine the IP address configuration of the
 *                      component.
 */
typedef struct pbuf * unsafe pbuf_p;

/** WiFi/xtcp data interface - mii.h equivalent
 *  TODO: document
 */
typedef interface xtcp_pbuf_if {

  /** TODO: document */
  [[clears_notification]]
  pbuf_p receive_packet();

  [[notification]]
  slave void packet_ready();

  /** TODO: document */
  void send_packet(pbuf_p p);

  // TODO: Add function to notify clients of received packets
} xtcp_pbuf_if;

typedef enum {
  ARP_TIMEOUT = 0,
  AUTOIP_TIMEOUT,
  TCP_TIMEOUT,
  IGMP_TIMEOUT,
  DHCP_COARSE_TIMEOUT,
  DHCP_FINE_TIMEOUT,
  NUM_TIMEOUTS
} xtcp_lwip_timeout_type;

void xtcp_lwip(server xtcp_if i_xtcp_init[n_xtcp], 
               static const unsigned n_xtcp,
               client mii_if ?i_mii,
               client ethernet_cfg_if ?i_eth_cfg,
               client ethernet_rx_if ?i_eth_rx,
               client ethernet_tx_if ?i_eth_tx,
               client smi_if ?i_smi,
               uint8_t phy_address,
               const char (&?mac_address0)[6],
               otp_ports_t &?otp_ports,
               xtcp_ipconfig_t &ipconfig);

void xtcp_uip(server xtcp_if i_xtcp_init[n_xtcp_init], 
              static const unsigned n_xtcp_init,
              client mii_if ?i_mii,
              client ethernet_cfg_if ?i_eth_cfg,
              client ethernet_rx_if ?i_eth_rx,
              client ethernet_tx_if ?i_eth_tx,
              client smi_if ?i_smi,
              uint8_t phy_address,
              const char (&?mac_address0)[6],
              otp_ports_t &?otp_ports,
              xtcp_ipconfig_t &ipconfig);
#endif /* __XC__ */

/** Copy an IP address data structure.
 */
#define XTCP_IPADDR_CPY_(dest, src) do { dest[0] = src[0]; \
                                         dest[1] = src[1]; \
                                         dest[2] = src[2]; \
                                         dest[3] = src[3]; \
                                      } while (0)

/** Compare two IP address structures.
 */
#define XTCP_IPADDR_CMP_(a, b) (a[0] == b[0] && \
                                a[1] == b[1] && \
                                a[2] == b[2] && \
                                a[3] == b[3])

#endif // __xtcp_h__