// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/** Simple UDP connection test.
 *
 * Expects to connect to example/app_simple_echo
 *
 */

#include <ctype.h>
#include <string.h>

#include "app_udp_connect.h"
#include "debug_print.h"
#include "xassert.h"


// Defines
#define UDP_BUFFER_SIZE 300
#define UDP_CONNECT_PORT 15533
#define UDP_ADDR {192, 168, 200, 178}
#define UDP_MSG "xmos udp message!\n"

#define POLL_INTERVAL 600000000
#define INIT_VAL -1

static inline void printip(xtcp_ipaddr_t ipaddr) {
  debug_printf("IP: %d.%d.%d.%d\n", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

static int32_t connect_udp(client xtcp_if i_xtcp)
{
  xtcp_ipaddr_t udp_addr = UDP_ADDR;

  int32_t socket_id = i_xtcp.socket(XTCP_PROTOCOL_UDP);
  // create new connection on the port
  xtcp_error_code_t connect_result = i_xtcp.connect(socket_id, UDP_CONNECT_PORT, udp_addr);
  if (connect_result != XTCP_SUCCESS) {
    i_xtcp.close(socket_id);
    socket_id = INIT_VAL;
  } else {
    // debug_printf("Connected on port %d, %d\n", UDP_CONNECT_PORT, socket_id);
  }
  return socket_id;
}

void app_udp_connect(client xtcp_if i_xtcp) {
  int32_t connection_id = INIT_VAL;  // The connection to the port

  timer tmr;
  unsigned int time;

  // The buffers for exchanging data
  char rx_buffer[UDP_BUFFER_SIZE];

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

            connection_id = connect_udp(i_xtcp);
            if (connection_id == INIT_VAL) {
              debug_printf("Failed to connect on port %d\n", UDP_CONNECT_PORT);
            } else {
              debug_printf("Connected on port %d, %d\n", UDP_CONNECT_PORT, connection_id);
            }
            break;

          case XTCP_IFDOWN:
            debug_printf("IF-DOWN\n");
            // Tidy up and close any connections we have open
            if (connection_id != INIT_VAL) {
              i_xtcp.close(connection_id);
              connection_id = INIT_VAL;
            }
            break;

          case XTCP_NEW_CONNECTION:
            debug_printf("Unexpected new connection requested: %d\n", client_conn);
            break;

          case XTCP_RECV_DATA:
            int32_t data_len = i_xtcp.recv(client_conn, rx_buffer, UDP_BUFFER_SIZE);
            if (data_len < 0) {
              debug_printf("Error receiving data: %d\n", data_len);
            } else {
              xtcp_host_t ip = i_xtcp.get_ipconfig_remote(client_conn);
              debug_printf("Got data: %d bytes, from %d.%d.%d.%d:%d\n", data_len,
                          ip.ipaddr[0], ip.ipaddr[1], ip.ipaddr[2], ip.ipaddr[3], ip.port_number);

              rx_buffer[data_len] = '\0';
              debug_printf("Recvd data: %s\n", rx_buffer);
            }
            break;

          case XTCP_RECV_FROM_DATA:
            debug_printf("Unexpected, recvfrom: %d\n", client_conn);
            break;

          case XTCP_SENT_DATA:
            debug_printf("Unexpected, Sent data\n");
            break;

          case XTCP_RESEND_DATA:
            debug_printf("Unexpected, Resend data\n");
            break;

          case XTCP_CLOSED:
            i_xtcp.close(client_conn);
            connection_id = INIT_VAL;
            debug_printf("Unexpected, Closed connection: %d\n", client_conn);
            break;

          case XTCP_ABORTED:
            connection_id = INIT_VAL;
            debug_printf("Aborted connection: %d\n", client_conn);
            // The application should attempt reconnection to maintain the flow
            break;
        }
        break;

      // This is the periodic case, it occurs every POLL_INTERVAL timer ticks
      case tmr when timerafter(time) :> void:

        if (connection_id != INIT_VAL) {
          // Send a message to the outgoing port
          debug_printf("Sending message to outgoing port %d\n", UDP_CONNECT_PORT);
          int32_t length = strlen(UDP_MSG);
          int32_t send_result = i_xtcp.send(connection_id, UDP_MSG, length);
          if (send_result < 0) {
            debug_printf("Failed to send message to outgoing port %d\n", UDP_CONNECT_PORT);
          } else {
            debug_printf("Sent message: %s\n", UDP_MSG);
          }
        }
        time += POLL_INTERVAL;
        break;
    }
  }
}
