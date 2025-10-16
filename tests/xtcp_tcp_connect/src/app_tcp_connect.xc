// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/** Simple TCP connection test.
 *
 * Expects to connect to example/app_simple_echo
 */

#include <ctype.h>
#include <string.h>

#include "app_tcp_connect.h"
#include "debug_print.h"
#include "xassert.h"


// Defines
#define TCP_BUFFER_SIZE 300
#define TCP_CONNECT_PORT 15534
#define TCP_ADDR {192, 168, 200, 178}
#define TCP_MSG "xmos tcp message!\n"

#define POLL_INTERVAL 600000000
#define INIT_VAL -1

static inline void printip(xtcp_ipaddr_t ipaddr) {
  debug_printf("IP: %d.%d.%d.%d\n", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

static int32_t connect_tcp(client xtcp_if i_xtcp)
{
  xtcp_ipaddr_t tcp_addr = TCP_ADDR;
  
  int32_t socket_id = i_xtcp.socket(XTCP_PROTOCOL_TCP);
  // create new connections on the outgoing port
  int32_t connect_result = i_xtcp.connect(socket_id, TCP_CONNECT_PORT, tcp_addr);
  if (connect_result < 0) {
    debug_printf("Failed to connect on port %d, %i\n", TCP_CONNECT_PORT, connect_result);
    i_xtcp.close(socket_id);
    socket_id = INIT_VAL;
  }
  return socket_id;
}

void app_tcp_connect(client xtcp_if i_xtcp) {
  int32_t connection_id = INIT_VAL;  // The connection id for the tcp connection
  int32_t connection_state = 0;  // The state of the connection
  
  timer tmr;
  unsigned int time;

  // The buffers for exchanging data
  char rx_buffer[TCP_BUFFER_SIZE];

  tmr :> time;
  time += POLL_INTERVAL;
  
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

            // create new connections on the outgoing port
            connection_id = connect_tcp(i_xtcp);
            if (connection_id < 0) {
              debug_printf("Failed to connect on port %d, %i\n", TCP_CONNECT_PORT, connection_id);
            } else {
              debug_printf("Connecting on port %d, %d\n", TCP_CONNECT_PORT, connection_id);
            }
            break;

          case XTCP_IFDOWN:
            debug_printf("IF-DOWN\n");
            // Tidy up and close any connections we have open
            if (connection_id != INIT_VAL) {
              i_xtcp.close(connection_id);
              connection_id = INIT_VAL;
              connection_state = 0;
            }
            break;

          case XTCP_ACCEPTED:
            debug_printf("Unexpected accept: %d\n", client_conn);
            break;

          case XTCP_NEW_CONNECTION:
            debug_printf("New connection event: %d\n", client_conn);
            if (connection_id == client_conn) {
              connection_state = 1;
            }
            break;

          case XTCP_RECV_DATA:
            int32_t data_len = i_xtcp.recv(client_conn, rx_buffer, TCP_BUFFER_SIZE);
            if (data_len < 0) {
              debug_printf("Error receiving data: %d\n", data_len);
            } else {
              xtcp_remote_t ip = i_xtcp.get_ipconfig_remote(client_conn);
              debug_printf("Got data: %d bytes, from %d.%d.%d.%d:%d\n", data_len,
                          ip.ipaddr[0], ip.ipaddr[1], ip.ipaddr[2], ip.ipaddr[3], ip.port_number);

              rx_buffer[data_len] = '\0';
              debug_printf("Recvd data: %s\n", rx_buffer);
            }
            break;

          case XTCP_SENT_DATA:
            if (client_conn == connection_id) {
              debug_printf("Sent Response\n");
            }
            break;

          case XTCP_RESEND_DATA:
            int32_t length = strlen(TCP_MSG);
            int32_t send_result = i_xtcp.send(connection_id, TCP_MSG, length);
            if (send_result < 0) {
              debug_printf("Failed to send message to outgoing port %d\n", TCP_CONNECT_PORT);
            }
            break;

          case XTCP_CLOSED:
            // Closed by the remote host
            i_xtcp.close(client_conn);
            connection_id = INIT_VAL;
            connection_state = 0;
            debug_printf("Closed connection: %d\n", client_conn);
            // The application should attempt reconnection to maintain the flow
            break;

          case XTCP_TIMED_OUT:
            // Closed by protocol timeout or reset by remote host
            connection_id = INIT_VAL;
            connection_state = 0;
            debug_printf("Timed out connection: %d\n", client_conn);
            // The application should attempt reconnection to maintain the flow
            break;

          case XTCP_ABORTED:
            // Aborted by the remote host or local stack
            connection_id = INIT_VAL;
            connection_state = 0;
            debug_printf("Aborted connection: %d\n", client_conn);
            // The application should attempt reconnection to maintain the flow
            break;
        }
        break;

      // This is the periodic case, it occurs every POLL_INTERVAL timer ticks
      case tmr when timerafter(time) :> void:

        if (connection_state == 1 && connection_id != INIT_VAL) {
          // Send a message to the outgoing port
          debug_printf("Sending message to outgoing port %d\n", TCP_CONNECT_PORT);
          int32_t length = strlen(TCP_MSG);
          int32_t send_result = i_xtcp.send(connection_id, TCP_MSG, length);
          if (send_result < 0) {
            debug_printf("Failed to send message to outgoing port %d\n", TCP_CONNECT_PORT);
          } else {
            debug_printf("Sent message: %s\n", TCP_MSG);
          }
        }
        time += POLL_INTERVAL;
        break;
    }
  }
}
