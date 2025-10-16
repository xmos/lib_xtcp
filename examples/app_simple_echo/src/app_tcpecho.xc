// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/**
 * TCP echo server example
 *
 * Echos all bytes sent by connecting clients, converting to uppercase.
 *
 */

#include <ctype.h>
#include <string.h>

#include "app_tcpecho.h"
#include "debug_print.h"
#include "xassert.h"

// Defines
#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15534

#define ANY_ADDR {0, 0, 0, 0}
#define INIT_VAL -1

static const xtcp_ipaddr_t any_addr = ANY_ADDR;

static inline void printip(xtcp_ipaddr_t ipaddr) {
  debug_printf("IP: %d.%d.%d.%d\n", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Responds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 */
void tcp_echo(client xtcp_if i_xtcp) {
  int32_t listening_connection = INIT_VAL;  // The connection to the incoming port
  int32_t responding_connection = INIT_VAL;  // The connection to the incoming port

  // The buffers for incoming data, outgoing responses and outgoing broadcast messages
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];

  int response_len;   // The length of the response the thread is sending

  while (1) {
    int32_t client_conn;
    select {
      // Respond to an event from the tcp server
      case i_xtcp.event_ready():
        const xtcp_event_type_t event = i_xtcp.get_event(client_conn);
        switch (event) {
          case XTCP_EVENT_NONE:
            // No event to process
            break;
          
          case XTCP_IFUP:
            // Show the IP address of the interface
            xtcp_ipconfig_t ipconfig = i_xtcp.get_netif_ipconfig(0);
            printip(ipconfig.ipaddr);

            listening_connection = i_xtcp.socket(XTCP_PROTOCOL_TCP);
            // Instruct server to listen and create new connections on the incoming port
            int32_t listen_result = i_xtcp.listen(listening_connection, INCOMING_PORT, any_addr);
            if (listen_result == XTCP_EINUSE) {
              debug_printf("Port still in use, connection not closed by remote host? %d\n", INCOMING_PORT);
            } else if (listen_result < 0) {
              debug_printf("Failed to listen on port %d, %i\n", INCOMING_PORT, listen_result);
            } else {
              debug_printf("Listening on port %d, %d\n", INCOMING_PORT, listening_connection);
            }
            break;

          case XTCP_IFDOWN:
            debug_printf("IF-DOWN\n");
            // Tidy up and close any connections we have open
            if (responding_connection != INIT_VAL) {
              i_xtcp.close(responding_connection);
              responding_connection = INIT_VAL;
            }
            if (listening_connection != INIT_VAL) {
              i_xtcp.close(listening_connection);
              listening_connection = INIT_VAL;
            }
            break;

          case XTCP_ACCEPTED:
            if (responding_connection == INIT_VAL) {
              responding_connection = client_conn;
              debug_printf("New connection accepted: %d\n", client_conn);
            } else {
              debug_printf("Unknown connection, closing %d\n", client_conn);
              i_xtcp.close(client_conn);
            }
            break;

          case XTCP_NEW_CONNECTION:
            // The tcp server is giving us a new connection.
            // It is either a remote host connecting on the listening port or the broadcast connection the threads asked
            // for with the xtcp_connect() call
            if (responding_connection == INIT_VAL) {
              responding_connection = client_conn;
              debug_printf("New connection listening: %d\n", client_conn);
            } else {
              debug_printf("Unknown connection, closing %d\n", client_conn);
              i_xtcp.close(client_conn);
            }
            break;

          case XTCP_RECV_DATA:
            // When we get a packet in:
            //
            //  - fill the tx buffer
            //  - send a response to that connection
            //
            int32_t data_len = i_xtcp.recv(client_conn, rx_buffer, RX_BUFFER_SIZE);
            if (data_len < 0) {
              debug_printf("Error receiving data: %d\n", data_len);
            } else {
              xtcp_host_t ip = i_xtcp.get_ipconfig_remote(client_conn);
              debug_printf("Got data: %d bytes, from %d.%d.%d.%d:%d\n", data_len,
                          ip.ipaddr[0], ip.ipaddr[1], ip.ipaddr[2], ip.ipaddr[3], ip.port_number);

              response_len = data_len;
              for (int i = 0; i < response_len; i++) tx_buffer[i] = toupper(rx_buffer[i]);

              int32_t result = i_xtcp.send(client_conn, tx_buffer, response_len);
              if (result < 0) {
                debug_printf("Error sending response: %d\n", result);
              } else {
                debug_printf("Sent response: %d bytes\n", response_len);
              }
            }
            break;

          case XTCP_SENT_DATA:
            // Notification that data has been sent
            if (client_conn == responding_connection) {
              debug_printf("Sent Response\n");
            }
            break;

          case XTCP_CLOSED:
            // Closed by the remote host, confirm and close our socket
            i_xtcp.close(client_conn);
            responding_connection = INIT_VAL;
            debug_printf("Closed connection: %d\n", client_conn);
            break;

          case XTCP_TIMED_OUT:
            // Closed by protocol timeout or reset by remote host
            responding_connection = INIT_VAL;
            debug_printf("Timed out connection: %d\n", client_conn);
            break;

          case XTCP_ABORTED:
            // Aborted by the remote host or local stack
            responding_connection = INIT_VAL;
            debug_printf("Aborted connection: %d\n", client_conn);
            break;
        }
        break;
    }
  }
}
