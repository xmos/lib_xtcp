// Copyright 2017-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "common.h"

#if defined BOARD_SUPPORT_BOARD && (BOARD_SUPPORT_BOARD == XK_EVK_XE216)
#include "xk_evk_xe216/board.h"
#endif

#ifndef BUSY
#define BUSY 0
#endif

static void reverse_copy(char out_buf[], char in_buf[], int data_len) {
  for (int i = 0; i < data_len; i++) {
    const int reverse_i = (data_len - 1) - i;
    out_buf[i] = in_buf[reverse_i];
  }
}

/** Simple TCP/UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Responds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *
 */
void reflect(client xtcp_if i_xtcp, int start_port) {
  // So we can handle multiple connections in one process
  reflect_state_t connection_states[OPEN_PORTS_PER_PROCESS];
#if BUSY
  // Timer for busy client, that handles data in bursts
  timer tmr;
#endif

  // The buffers for incoming data and outgoing responses
  char tx_buffer[OPEN_PORTS_PER_PROCESS][RX_BUFFER_SIZE];
  int response_lens[OPEN_PORTS_PER_PROCESS];

  // Instruct server to listen and create new connections on the incoming port
  for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
    connection_states[i].active = 0;
    connection_states[i].local_port = (start_port + i);
    connection_states[i].socket_id = INIT_VAL;
    for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
      connection_states[i].tcp_id[j] = INIT_VAL;
    }
  }

#if defined TEST_BOARD_SUPPORT_BOARD && (TEST_BOARD_SUPPORT_BOARD == XK_ETH_XU316_DUAL_100M)
#ifdef XCORE_AI_MULTI_PHY_SINGLE_PHY
  debug_printf("Configuration: single-phy\n");
#else
  debug_printf("Configuration: dual-phy\n");
#endif

#elif defined BOARD_SUPPORT_BOARD && (BOARD_SUPPORT_BOARD == XK_EVK_XE216)
  debug_printf("Configuration: XE216 EVK\n");

#elif defined BOARD_SUPPORT_BOARD && (BOARD_SUPPORT_BOARD == XK_ETH_316_DUAL)
  debug_printf("Configuration: XK-ETH-316-DUAL\n");
#else
#error "Unknown board configuration"
#endif

  // unsigned data_len = 0;
  char rx_tmp[RX_BUFFER_SIZE];
  xtcp_ipaddr_t any_addr = {0, 0, 0, 0};

  while (1) {
    // A temporary variable to hold connections associated with an event
    int32_t conn_id;

    select {
      // Respond to an event from the tcp server
      case i_xtcp.event_ready(): {
        const xtcp_event_type_t event = i_xtcp.get_event(conn_id);
        switch (event) {
          case XTCP_EVENT_NONE:
            // No event to process
            break;

          case XTCP_IFUP:
            debug_printf("IFUP\n");
            for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
              reflect_state_t *socket = &connection_states[i];
              socket->socket_id = i_xtcp.socket(PROTOCOL);

              int32_t listen_result = i_xtcp.listen(socket->socket_id, socket->local_port, any_addr);
              if (listen_result < 0) {
                debug_printf("Failed to listen on port %d, %i\n", socket->local_port, listen_result);
              } else {
                debug_printf("Listening on port: %d\n", socket->local_port);
                if (PROTOCOL == XTCP_PROTOCOL_UDP) {
                  // No connection event for UDP, mark as active
                  socket->active = 1;
                  // connection_states[i].socket_id = connection_states[i].conn_id;
                }
              }
            }
            break;

          case XTCP_IFDOWN:
            // Tidy up and close any connections we have open
            debug_printf("IFDOWN\n");
            for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
              reflect_state_t *socket = &connection_states[i];

              if (socket->active) {
                socket->active = 0;
                // UDP - closes the socket (listening and data)
                // TCP - closes listening socket
                i_xtcp.close(socket->socket_id);
                socket->socket_id = INIT_VAL;

                for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
                  if (socket->tcp_id[j] != INIT_VAL) {
                    // TCP - close data socket
                    i_xtcp.close(socket->tcp_id[j]);
                    socket->tcp_id[j] = INIT_VAL;
                  }
                }
                response_lens[i] = INIT_VAL;
              }
            }
            break;

          case XTCP_ACCEPTED:
            int k;
            for (int k = 0; k < OPEN_PORTS_PER_PROCESS; k++) {
              reflect_state_t *socket = &connection_states[k];

              xtcp_host_t ipaddr = i_xtcp.get_ipconfig_local(conn_id);
              if (socket->local_port == ipaddr.port_number) {
                if (!socket->active) {
                  debug_printf("New connection accepted: %d\n", conn_id);
                  socket->active = 1;
                  socket->tcp_id[0] = conn_id;
                } else {
                  for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
                    if (socket->tcp_id[j] == INIT_VAL) {
                      socket->tcp_id[j] = conn_id;
                      debug_printf("New concurrent connection accepted: %d\n", conn_id);
                      break;
                    }
                  }
                }
                break;
              }
            }

            if (k == OPEN_PORTS_PER_PROCESS) {
              debug_printf("Error: failed conn: %d\n", conn_id);
              // If no free connection slots were found, abort the connection
              i_xtcp.abort(conn_id);
            }
            break;

          case XTCP_RECV_DATA:
#if BUSY
            // We are a busy client, so delay before accessing recv data.
            // This allows the remote tester to send more data and exercise the queueing
            {
              unsigned now;
              tmr :> now;
              tmr when timerafter(now + (XS1_TIMER_KHZ * BUSY)) :> now;
            }
#endif
            // TCP only
            for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
              reflect_state_t *socket = &connection_states[i];

              for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
                if (socket->tcp_id[j] == conn_id) {
                  int32_t data_len = i_xtcp.recv(conn_id, rx_tmp, RX_BUFFER_SIZE);

                  if (rx_tmp[0] != 'a') {
                    // Only echo data that is not 'a' (used to terminate the test)
                    reverse_copy(tx_buffer[i], rx_tmp, data_len);
                    response_lens[i] = data_len;
                    int32_t result = i_xtcp.send(conn_id, tx_buffer[i], response_lens[i]);
                    if (result < 0) {
                      debug_printf("Error sending response: %d\n", result);
                    }
                  }
                  break;
                }
              }
            }
            break;

          case XTCP_RECV_FROM_DATA:
#if BUSY
            // We are a busy client, so delay before accessing recv data.
            {
              unsigned now;
              tmr :> now;
              tmr when timerafter(now + (XS1_TIMER_KHZ * BUSY)) :> now;
            }
#endif
            // UDP only
            uint16_t port_number = 0;
            xtcp_ipaddr_t ipaddr = {0, 0, 0, 0};
            int index;
            int is_active = 0;
            for (index = 0; index < OPEN_PORTS_PER_PROCESS; index++) {
              if (connection_states[index].socket_id == conn_id) {
                is_active = 1;
                break;
              }
            }
            if (is_active == 0) {
              // No existing connection, so try and find an empty connection slot
              for (index = 0; index < OPEN_PORTS_PER_PROCESS; index++) {
                if (!connection_states[index].active) {
                  debug_printf("WARNING: new conn from rx data: %d\n", conn_id);
                  // Otherwise, assign the connection to a slot
                  connection_states[index].active = 1;
                  connection_states[index].socket_id = conn_id;
                  is_active = 1;
                  break;
                } else {
                  debug_printf("Recv data rejected: %d\n", conn_id);
                }
              }
            }
            if (is_active) {
              int32_t data_len = i_xtcp.recvfrom(conn_id, rx_tmp, RX_BUFFER_SIZE, ipaddr, port_number);
              if (rx_tmp[0] != 'a') {
                // Only echo data that is not 'a' (used to terminate the test)
                reverse_copy(tx_buffer[index], rx_tmp, data_len);
                response_lens[index] = data_len;
                int32_t result = i_xtcp.sendto(conn_id, tx_buffer[index], response_lens[index], ipaddr, port_number);
                if (result < 0) {
                  debug_printf("Error sendto response: %d\n", result);
                }
              } else {
                // If UDP we will not receive a close event, so handle 'a' here
                exit(0);
              }
            }
            break;

          case XTCP_RESEND_DATA:
            for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
              if (connection_states[i].tcp_id == conn_id) {
                i_xtcp.send(conn_id, tx_buffer[i], response_lens[i]);
                break;
              }
            }
            break;

          case XTCP_SENT_DATA:
            // Notification that data has been sent, via TCP
            break;

          case XTCP_CLOSED:
            for (int t = 0; t < OPEN_PORTS_PER_PROCESS; t++) {
              reflect_state_t *socket = &connection_states[t];

              // Slight hack to kill off process once python script finishes
              if (rx_tmp[0] == 'a') {
                exit(0);
              }

              if (socket->active) {
                socket->active = 0;
                response_lens[t] = INIT_VAL;
              }
              for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
                
                if (socket->tcp_id[j] == conn_id) {
                  debug_printf("closing (%d): %c\n", conn_id, rx_tmp[0]);
                  i_xtcp.close(socket->tcp_id[j]);
                  socket->tcp_id[j] = INIT_VAL;
                  break;
                }
              }
            }
            break;

          case XTCP_ABORTED:
            for (int t = 0; t < OPEN_PORTS_PER_PROCESS; t++) {
              reflect_state_t *socket = &connection_states[t];

              if (socket->active) {
                socket->active = 0;
                debug_printf("Aborted connection: %d\n", conn_id);

                for (int j = 0; j < CONCURRENT_TCP_PORTS; j++) {
                  if (socket->tcp_id[j] == conn_id) {
                    socket->tcp_id[j] = INIT_VAL;
                    break;
                  }
                }
                if (socket->socket_id == conn_id) {
                  socket->socket_id = INIT_VAL;
                }
                response_lens[t] = INIT_VAL;
              }
            }
            break;
        }
        break;
      }
    }
  }
}
