// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/**
 * UDP echo server example
 *
 * Echos all bytes sent by connecting clients, converting to uppercase.
 *
 */

#include <ctype.h>
#include <string.h>

#include "app_udpecho.h"
#include "debug_print.h"
#include "xassert.h"

// Defines
#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15533

#define ANY_ADDR {0, 0, 0, 0}
#define INIT_VAL -1

static inline void printip(xtcp_ipaddr_t ipaddr) {
  debug_printf("IP: %d.%d.%d.%d\n", ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
}

/** Simple UDP reflection thread.
 *
 *   - Responds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *
 */
void udp_echo(client xtcp_if i_xtcp) {
  int32_t responding_connection = INIT_VAL;  // The connection to the incoming port
  xtcp_ipaddr_t any_addr = ANY_ADDR;

  // The buffers for incoming data, outgoing responses and outgoing broadcast messages
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];
  int32_t dns_lookup = 0;
  int32_t dns_retries = 0;
  const uint8_t hostname[] = "www.xmos.com";
  xtcp_ipaddr_t dns_server = {8, 8, 8, 8};

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

            responding_connection = i_xtcp.socket(XTCP_PROTOCOL_UDP);
            // Instruct server to listen and create new connections on the incoming port
            int32_t listen_result = i_xtcp.listen(responding_connection, INCOMING_PORT, any_addr);
            if (listen_result < 0) {
              debug_printf("Failed to listen on port %d, %i\n", INCOMING_PORT, listen_result);
            } else {
              debug_printf("Listening on port %d, %d\n", INCOMING_PORT, responding_connection);
            }
            break;

          case XTCP_IFDOWN:
            debug_printf("IF-DOWN\n");
            // Tidy up and close any connections we have open
            if (responding_connection != INIT_VAL) {
              i_xtcp.close(responding_connection);
              responding_connection = INIT_VAL;
            }
            dns_lookup = 0;
            break;

          case XTCP_NEW_CONNECTION:
            debug_printf("Unexpected, New broadcast connection request: %d\n", client_conn);
            break;

          case XTCP_RECV_FROM_DATA:
            // Notification we have received data from a remote host on this connection
            // We can now read the data, process it and send a response
            uint16_t port_number = 0;
            xtcp_ipaddr_t ipaddr = {0, 0, 0, 0};
            int32_t data_len = i_xtcp.recvfrom(client_conn, rx_buffer, RX_BUFFER_SIZE, ipaddr, port_number);
            if (data_len < 0) {
              debug_printf("Error receiving data: %d\n", data_len);
            } else {
              debug_printf("Got data: %d bytes, from %d.%d.%d.%d:%d\n", data_len,
                          ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3], port_number);

              for (int i = 0; i < data_len; i++) tx_buffer[i] = toupper(rx_buffer[i]);

              int32_t result = i_xtcp.sendto(client_conn, tx_buffer, data_len, ipaddr, port_number);
              if (result < 0) {
                debug_printf("Error sending response: %d\n", result);
              } else {
                debug_printf("Sent response: %d bytes\n", data_len);
              }

              // Example DNS lookup, note DNS aserver and host name need to be configured.
              if (!dns_lookup) {
                dns_lookup = 1;
                xtcp_remote_t dns_result = i_xtcp.request_host_by_name(hostname, sizeof(hostname), dns_server);
                if (dns_result.ipaddr[0] == 0) {
                  debug_printf("DNS request pending...\n");
                } else {
                  debug_printf("Requested DNS lookup for %s, %d.%d.%d.%d\n", hostname,
                               dns_result.ipaddr[0], dns_result.ipaddr[1], dns_result.ipaddr[2], dns_result.ipaddr[3]);
                }
              }
            }
            break;

          case XTCP_RECV_DATA:
            debug_printf("Unexpected, Received data notification\n");
            break;

          case XTCP_SENT_DATA:
            debug_printf("Unexpected, Sent data notification\n");
            break;

          case XTCP_TIMED_OUT:
          case XTCP_ABORTED:
          case XTCP_CLOSED:
            debug_printf("Unexpected, Closed connection: %d\n", client_conn);
            // No need to close socket as it remains listening for new connections
            break;

          case XTCP_DNS_RESULT:
            // client_conn == xtcp_error_code_t, as it does not relate to any connection.

            xtcp_error_code_t request = client_conn;
            if (request == XTCP_SUCCESS) {
              debug_printf("DNS response: success\n");
              if (dns_retries == 0) {
                dns_retries = 1;
                xtcp_remote_t dns_result = i_xtcp.request_host_by_name(hostname, sizeof(hostname), dns_server);
                if (dns_result.ipaddr[0] == 0) {
                  debug_printf("DNS lookup failed, second request pending...\n");
                } else {
                  debug_printf("Requested DNS lookup for %s, %d.%d.%d.%d\n", hostname,
                               dns_result.ipaddr[0], dns_result.ipaddr[1], dns_result.ipaddr[2], dns_result.ipaddr[3]);
                }
              }

            } else if (request == XTCP_ENOMEM) {
              // DNS request failed, e.g. server incorrect or not reachable
              debug_printf("DNS response: request failed\n");
            } else if (request == XTCP_EINVAL) {
              // DNS request invalid argument
              debug_printf("DNS response: bad argument\n");
            }
            break;
        }
        break;
    }
  }
}
