// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __xtcp_h__
#define __xtcp_h__

#include <limits.h>
#include <mii.h>
#include <smi.h>
#include <ethernet.h>
// TODO - remove dependency on OTP
#include <otp_board_info.h>
#include <xccompat.h>

#include "xc2compat.h"

#ifdef __xtcp_conf_h_exists__
#include "xtcp_conf.h"
#endif

#ifdef __xtcp_client_conf_h_exists__
#include "xtcp_client_conf.h"
#endif

/** Used by the LWIP callback functions to
 *  correctly pass packets to the DHCP functions
 */
#define DHCPC_SERVER_PORT 67
#define DHCPC_CLIENT_PORT 68

/** Ethernet network interface hostname. Option LWIP_NETIF_HOSTNAME=1 required in lwipopts.h. */
#ifndef XTCP_HOSTNAME
#define XTCP_HOSTNAME "lwip-xcore"
#endif

/** Maximum number of connected XTCP clients */
#ifndef MAX_XTCP_CLIENTS
#define MAX_XTCP_CLIENTS 5
#endif

/** Maximum number of events in a client queue */
#ifndef CLIENT_QUEUE_SIZE
#define CLIENT_QUEUE_SIZE 20
#endif

/** Minimum number of bytes lib_xtcp can successfully transmit, small packets will be padded to this size */
#define ETHERNET_MIN_FRAME_SIZE 60

/** XTCP IP address.
 *
 *  This data type represents a single ipv4 address in the XTCP
 *  stack.
 */
typedef uint8_t xtcp_ipaddr_t[4];

/** XTCP host's address.
 *
 *  This data type represents a single ipv4 address in the XTCP
 *  stack.
 */
typedef struct xtcp_host_t {
  xtcp_ipaddr_t ipaddr; /**< The IP Address of the remote host */
  uint16_t port_number; /**< The port number of the remote host */
} xtcp_host_t;

/** IP configuration information structure.
 *
 *  This structure describes IP configuration for an ip node.
 *
 */
typedef struct xtcp_ipconfig_t {
  xtcp_ipaddr_t ipaddr;  /**< The IP Address of the node */
  xtcp_ipaddr_t netmask; /**< The netmask of the node. The mask used to determine which address are routed locally.*/
  xtcp_ipaddr_t gateway; /**< The gateway of the node */
} xtcp_ipconfig_t;

/** XTCP protocol type.
 *
 * This determines what type a connection is: either UDP or TCP.
 *
 */
typedef enum xtcp_protocol_t {
  XTCP_PROTOCOL_NONE, /**< No Protocol */
  XTCP_PROTOCOL_TCP,  /**< Transmission Control Protocol */
  XTCP_PROTOCOL_UDP   /**< User Datagram Protocol */
} xtcp_protocol_t;

/** XTCP event type.
 *
 *  The event type represents what event is occurring on a particular connection.
 *  It is created by calling socket() and accessed by get_event() and after event_ready().
 *
 */
typedef enum xtcp_event_type_t {
  /** No event */
  XTCP_EVENT_NONE,

  /** This event represents a new connection has been made. For TCP client connections it occurs when a stream is setup
   * with the remote host. */
  XTCP_NEW_CONNECTION,

  /** This event occurs when a listening TCP socket has received a connection request from a remote host. */
  XTCP_ACCEPTED,

  /** This event occurs when the connection has received some data. Call recv() to access the data. */
  XTCP_RECV_DATA,

  /** This event occurs when the connection has received some data from a remote host, UDP only. Call recvfrom() to access the data. */
  XTCP_RECV_FROM_DATA,

  /** This event occurs when the server has successfully sent the previous piece of TCP data that was given to it via a
   * call to send(). */
  XTCP_SENT_DATA,

  /** This event occurs when the local host has failed to send the previous piece of data that was given to it via a call to
   * send(). The stack is now requesting for the same data to be sent again. */
  XTCP_RESEND_DATA,

  /** This event occurs when the connection request has timed out or been reset by the remote host (TCP only). This event represents the
   * closing of a connection and is the last event that will occur on an active connection. */
  XTCP_TIMED_OUT,

  /** This event occurs when the connection has been aborted by the local or remote host (TCP only).
   * This event represents the closing of a connection and is the last event that will occur on an active connection. */
  XTCP_ABORTED,

  /** This event occurs when the connection has been closed by the local or remote host, TCP only. This event represents the
   * closing of a connection and is the last event that will occur on an active connection. */
  XTCP_CLOSED,

  /** This event occurs when the link goes up (with valid new ip address). This event has no associated connection. */
  XTCP_IFUP,

  /** This event occurs when the link goes down. This event has no associated connection. */
  XTCP_IFDOWN,

  /** This event occurs when the XTCP connection has a DNS result for a request.
   * There is no connection associated with this event, so the "id" returned by get_event() is the DNS return code as a xtcp_error_code_t.
   * XTCP_SUCCESS for successful resolution. XTCP_EINVAL for invalid argument. XTCP_ENOMEM for DNS request failed. */
  XTCP_DNS_RESULT
} xtcp_event_type_t;

/** XTCP error codes.
 *
 *  This type represents the error codes that can be returned by
 *  various XTCP functions.
 *
 */
typedef enum xtcp_error_code_t
{
  XTCP_SUCCESS = 0,           /**< Success */
  XTCP_EINVAL = -1,           /**< Invalid argument */
  XTCP_ENOMEM = -2,           /**< Out of memory */
  XTCP_EAGAIN = -3,           /**< Resource temporarily unavailable */
  XTCP_EPROTONOSUPPORT = -4,  /**< Protocol not supported */ 
  XTCP_EINUSE = -5,           /**< Address in use */
} xtcp_error_code_t;

/** This type represents an int32_t with a status value.
 *
 *  This is a type used to return both a status code and an int32_t value.
 *
 **/
typedef struct xtcp_error_int32_t {
  xtcp_error_code_t status; /**< The status of the operation */
  int32_t value;            /**< The int32_t value of the operation */
} xtcp_error_int32_t;

#if defined(__XC__) || defined(__DOXYGEN__)
#ifndef __DOXYGEN__
typedef interface xtcp_if {
#endif
  /** \addtogroup xtcp_if
   * 
   * The client interface for lib_xtcp
   * \{
   */

  /** \brief Notifies the client that there is data/information
   *         ready for them.
   *
   *  After this notification is raised a call to get_event() is needed.
   */
  [[notification]] slave void event_ready();

  /** \brief Receive information/data from the XTCP server.
   *
   *  After the client is notified by event_ready() it must call this function
   *  to receive the event from the server.
   *
   * \note When receiving a new connection event on a TCP socket, the id will denote the new connection socket.
   *
   * \param id Output parameter for the connection descriptor the event occurred on.
   * \returns     The event type produced on the given connection.
   */
  [[clears_notification]] xtcp_event_type_t get_event(REFERENCE_PARAM(int32_t, id));

  /** \brief Create an xtcp socket
   *
   *  \param protocol   The protocol for any communication over the returned connection.
   *  \returns          A xtcp connection descriptor that will be used to refer to this socket in future calls.
   *
   * \see close()
   */
  int32_t socket(xtcp_protocol_t protocol);

  /** \brief Close a connection.
   *
   *  May still receive data on a TCP connection after this call, until the close session hand-shake has completed with
   * the remote-host. Use abort() if you wish to stop all data immediately.
   *
   *  If this is TCP socket was a remote-host triggered connection on a listening socket, it will continue to listen on
   *  the assigned port.
   *
   *  If this TCP socket was a local-host triggered connection, it will close the connection.
   *
   *  If this is a UDP socket, it will close the connection and stop listening on the assigned port.
   *
   * \note The id will become invalid after this call, so it should not be used.
   *
   * \param id The connection descriptor to act on.
   *
   * \see socket() and abort()
   */
  void close(int32_t id);

  /** \brief Abort a connection.
   *
   *  For UDP this is the same as closing the connection. For TCP the server will send a RST signal and stop all
   * incoming data, before closing the socket.
   *
   * \note id will become invalid after this call, so it should not be used.
   *
   * \param id The connection descriptor to act on.
   */
  void abort(int32_t id);

  /** \brief Listen to a particular incoming port.
   *
   *  After this call, when a TCP connection is established by a remote-host an XTCP_NEW_CONNECTION event is signalled.
   *  When processing the connection, this will create a new socket with the connection details of the remote-host. The
   *  original listening socket remains valid and active.
   *
   * \note  For TCP connections, the id parameter will be overwritten with the new connection descriptor.
   *
   *  For a UDP socket, this will bind on the specified port allowing incoming packets. Any data received will
   *  be passed as a data received event, XTCP_RECV_DATA.
   *
   * \param id       The connection descriptor to act on.
   * \param port_number The local port number to listen to.
   * \param ipaddr      The address of the local host.
   * \returns           XTCP_SUCCESS if successful, XTCP_EINVAL if invalid parameters are provided. Also, XTCP_EINUSE if the
   *                    connection is already active, and may require a TCP timeout before using again.
   *
   * \see close()
   */
  xtcp_error_code_t listen(int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr);

  /** \brief Try to connect to a remote port.
   *
   *  For TCP this will initiate the remote-host handshake.
   *
   *  For UDP this will assign a local port and bind the remote address of the connection to the host specified. This
   * sends no network traffic.
   *
   * \param id       The connection descriptor to act on.
   * \param port_number The remote port to associate with the connection.
   * \param ipaddr      The address of the remote host.
   * \returns           XTCP_SUCCESS if successful, XTCP_EINVAL if invalid parameters are provided.
   */
  xtcp_error_code_t connect(int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr);

  /** \brief Send data to the connection.
   *
   * \param id       The connection descriptor to act on.
   * \param buffer        An array of data to be transmitted on the network.
   * \param length      The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   * \returns           The number of bytes accepted by xtcp or a negative xtcp_error_code_t.
   */
  int32_t send(int32_t id, const uint8_t buffer[length], uint32_t length);

  /** \brief Send data to the connection.
   *
   * \param id       The connection descriptor to act on.
   * \param buffer        An array of data to be transmitted on the network.
   * \param length      The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   * \param ts          The packet transmit timestamp.
   * \returns           The number of bytes accepted by xtcp or a negative xtcp_error_code_t.
   */
  int32_t send_timed(int32_t id, const uint8_t buffer[length], uint32_t length, REFERENCE_PARAM(uint32_t, ts));

  /** \brief Send data to the connection.
   *
   * \param id       The connection descriptor to act on.
   * \param buffer        An array of data to be transmitted on the network.
   * \param length      The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   * \param remote_addr The address of the remote host.
   * \param remote_port The remote port of the remote host.
   * \returns           The number of bytes accepted by xtcp or an xtcp_error_code_t.
   */
  int32_t sendto(int32_t id, const uint8_t buffer[length], uint32_t length, xtcp_ipaddr_t remote_addr, uint16_t remote_port);

  /** \brief Send timestamped data to the connection.
   *
   * \param id       The connection descriptor to act on.
   * \param buffer        An array of data to be transmitted on the network.
   * \param length      The length of data to send. If this is 0, no data will
   *                    be sent and a XTCP_SENT_DATA event will not occur.
   * \param remote_addr The address of the remote host.
   * \param remote_port The remote port of the remote host.
   * \param ts          The packet transmit timestamp.
   * \returns           The number of bytes accepted by xtcp or an xtcp_error_code_t.
   */
  int32_t sendto_timed(int32_t id, const uint8_t buffer[length], uint32_t length, xtcp_ipaddr_t remote_addr, uint16_t remote_port, REFERENCE_PARAM(uint32_t, ts));

  /** \brief Receive data on a connection.
   *
   * Copies data from an internal buffer to the given buffer, if data is available.
   *
   *  If the data buffer is not large enough then an exception will be raised.
   *
   * \param id       The connection descriptor to act on.
   * \param buffer      The destination buffer where received data will be stored.
   * \param length      The length of the given buffer and the maximum amount of data that will be copied.
   * \returns           Either the total number of bytes copied to the given buffer or an xtcp_error_code_t.
   */
  int32_t recv(int32_t id, uint8_t buffer[length], uint32_t length);

  /** \brief Receive timestamped data on a connection.
   *
   * Copies data from an internal buffer to the given buffer, if data is available.
   *
   *  If the data buffer is not large enough then an exception will be raised.
   *
   * \param id          The connection descriptor to act on.
   * \param buffer      The destination buffer where received data will be stored.
   * \param length      The length of the given buffer and the maximum amount of data that will be copied.
   * \param ts          The packet receive timestamp.
   * \returns           Either the total number of bytes copied to the given buffer or an xtcp_error_code_t.
   */
  int32_t recv_timed(int32_t id, uint8_t buffer[length], uint32_t length, REFERENCE_PARAM(uint32_t, ts));

  /** \brief Receive data on a connection, remote host and port.
   *
   * Copies data from an internal buffer to the given buffer, if data is available.
   *
   *  If the data buffer is not large enough then an exception will be raised.
   *
   * \param id          The connection descriptor to act on.
   * \param buffer      The destination buffer where received data will be stored.
   * \param length      The length of the given buffer and the maximum amount of data that will be copied.
   * \param port_number The remote port buffer data was received from.
   * \param ipaddr      The address of the remote host.
   * \returns           Either the total number of bytes copied to the given buffer or an xtcp_error_code_t.
   */
  int32_t recvfrom(int32_t id, uint8_t buffer[length], uint32_t length, REFERENCE_PARAM(xtcp_ipaddr_t, ipaddr), REFERENCE_PARAM(uint16_t, port_number));

  /** \brief Receive timestamped data on a connection, remote host and port.
   *
   * Copies data from an internal buffer to the given buffer, if data is available.
   *
   *  If the data buffer is not large enough then an exception will be raised.
   *
   * \param id          The connection descriptor to act on.
   * \param buffer      The destination buffer where received data will be stored.
   * \param length      The length of the given buffer and the maximum amount of data that will be copied.
   * \param port_number The remote port buffer data was received from.
   * \param ipaddr      The address of the remote host.
   * \param ts          The packet receive timestamp.
   * \returns           Either the total number of bytes copied to the given buffer or an xtcp_error_code_t.
   */
  int32_t recvfrom_timed(int32_t id, uint8_t buffer[length], uint32_t length, REFERENCE_PARAM(xtcp_ipaddr_t, ipaddr), REFERENCE_PARAM(uint16_t, port_number), REFERENCE_PARAM(uint32_t, ts));

  /** \brief Fill the provided ipconfig address with the current state of the interface.
   *
   * \param netif_id    The network interface ID to get the IP config for.
   * 
   * \returns           The current IP configuration of the interface.
   */
  xtcp_ipconfig_t get_netif_ipconfig(int32_t netif_id);

  /** \brief Fill the provided ipconfig address with the current remote host for the connection.
   *
   * \param id          The connection descriptor
   *
   * \returns           The current remote host for the connection.
   *
   * \note For UDP connections this will be unset unless connect() has been called.
   */
  xtcp_host_t get_ipconfig_remote(int32_t id);

  /** \brief Fill the provided ipconfig address with the current local host for the connection.
   *
   * \param id          The connection descriptor
   *
   * \returns           The current local host for the connection.
   *
   * \note For UDP connections this will be unset unless connect() has been called.
   */
  xtcp_host_t get_ipconfig_local(int32_t id);

  /** \brief Allows the client to record additional data alongside the connection.
   *
   * \param id          The connection descriptor to set the state for.
   * \param data        A pointer to the additional data to associate with the connection.
   *
   * \returns           0 on success, or a negative error code on failure.
   */
  int32_t set_connection_client_data(int32_t id, void *unsafe data);

  /** \brief Allows the client to retrieve additional data alongside the connection.
   *
   * \param id          The connection descriptor to set the state for.
   *
   * \returns           Pointer to the additional data associated with the connection, or NULL if not set.
   */
  void *unsafe get_connection_client_data(int32_t id);

  /** \brief Subscribe to a particular IP multicast group address.
   *
   * \param addr        The address of the multicast group to join. It is
   *                    assumed that this is a multicast IP address.
   */
  void join_multicast_group(xtcp_ipaddr_t addr);

  /** \brief Unsubscribe from a particular IP multicast group address.
   *
   * \param addr        The address of the multicast group to leave. It is
   *                    assumed that this is a multicast IP address.
   */
  void leave_multicast_group(xtcp_ipaddr_t addr);

  /** \brief Request a host's IP address from its pretty name.
   *
   * \param hostname    The human readable host name, e.g. "www.xmos.com"
   * \param len         Length of hostname string
   * \param dns_server  IP address of DNS server to query
   * \returns           The remote host for the hostname
   * 
   * \note This is a non-blocking call. The result of the lookup will be indicated by an XTCP_DNS_RESULT event.
   */
  xtcp_host_t request_host_by_name(const uint8_t hostname[len], static_const_unsigned len, xtcp_ipaddr_t dns_server);

  /** \brief Query if the underlying interface is up.
   *
   * \returns           1 if the underlying interface us up, 0 otherwise.
   */
  int is_ifup(void);
  
  /** \} */
#ifndef __DOXYGEN__
} xtcp_if;
#endif

#ifndef __DOXYGEN__
typedef struct pbuf * unsafe pbuf_p;

/** WiFi/xtcp data interface - mii.h equivalent
 */
typedef interface xtcp_pbuf_if {

  /** TODO: document */
  [[clears_notification]]
  pbuf_p receive_packet();

  [[notification]]
  slave void packet_ready();

  /** TODO: document */
  void send_packet(pbuf_p p);

} xtcp_pbuf_if;
#endif

/** Function implementing the TCP/IP stack using the lwIP stack.
 *
 *  This functions implements a TCP/IP stack that clients can access via an interface.
 *
 *  \param i_xtcp       The interface array to connect to the clients.
 *  \param n_xtcp       The number of clients to the task.
 *  \param i_mii        If this component is connected to the mii() component in the Ethernet library then this
 *                      interface should be used to connect to it. Otherwise it should be set to null.
 *  \param i_eth_cfg    If this component is connected to an MAC component in the Ethernet library then this
 *                      interface should be used to connect to it. Otherwise it should be set to null.
 *  \param i_eth_rx     If this component is connected to an MAC component in the Ethernet library then this
 *                      interface should be used to connect to it. Otherwise it should be set to null.
 *  \param i_eth_tx     If this component is connected to an MAC component in the Ethernet library then this
 *                      interface should be used to connect to it. Otherwise it should be set to null.
 *  \param mac_address  If this array is non-null then it will be used to set the MAC address of the component.
 *  \param otp_ports    If this port structure is non-null then the component will obtain the MAC address from OTP ROM.
 *                      See the OTP reading library user guide for details.
 *  \param ipconfig     This `xtcp_ipconfig_t` structure is used to determine the IP address configuration of the
 *                      component.
 */
void xtcp_lwip(SERVER_INTERFACE_ARRAY(xtcp_if, i_xtcp, n_xtcp),
               static_const_unsigned n_xtcp,
               NULLABLE_CLIENT_INTERFACE(mii_if, i_mii),
               NULLABLE_CLIENT_INTERFACE(ethernet_cfg_if, i_eth_cfg),
               NULLABLE_CLIENT_INTERFACE(ethernet_rx_if, i_eth_rx),
               NULLABLE_CLIENT_INTERFACE(ethernet_tx_if, i_eth_tx),
               CONST_NULLABLE_ARRAY_OF_SIZE(char, mac_address0, MACADDR_NUM_BYTES),
               NULLABLE_REFERENCE_PARAM(otp_ports_t, otp_ports),
               REFERENCE_PARAM(xtcp_ipconfig_t, ipconfig));
#endif /* __XC__ || __DOXYGEN__ */

/** Copy an IP address data structure.
 */
#define XTCP_IPADDR_CPY(dest, src) do { dest[0] = src[0]; \
                                        dest[1] = src[1]; \
                                        dest[2] = src[2]; \
                                        dest[3] = src[3]; \
                                      } while (0)

/** Compare two IP address structures.
 */
#define XTCP_IPADDR_CMP(a, b) (a[0] == b[0] && \
                                a[1] == b[1] && \
                                a[2] == b[2] && \
                                a[3] == b[3])

#endif // __xtcp_h__
