// Copyright 2017-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "common.h"

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *   - Periodically sends out a fixed packet to a broadcast IP address.
 *
 */
void udp_reflect(client xtcp_if i_xtcp, int start_port) {
  // So we can handle multiple connections in one process
  reflect_state_t connection_states[OPEN_PORTS_PER_PROCESS];

  // The buffers for incoming data and outgoing responses
  char tx_buffer[OPEN_PORTS_PER_PROCESS][RX_BUFFER_SIZE];
  int response_lens[OPEN_PORTS_PER_PROCESS];

  // Instruct server to listen and create new connections on the incoming port
  for (int i = start_port; i < start_port + OPEN_PORTS_PER_PROCESS; i++) {
    debug_printf("Listening on port: %d\n", i);
    i_xtcp.listen(i, PROTOCOL);
  }

  for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
    connection_states[i].active = 0;
    connection_states[i].conn_id = INIT_VAL;
  }
  
#ifdef XCORE_AI_MULTI_PHY_SINGLE_PHY
  debug_printf("Configuration: single-phy\n");
#else
  debug_printf("Configuration: dual-phy\n");
#endif

  unsigned data_len = 0;
  char rx_tmp[RX_BUFFER_SIZE];

  while (1) {
    // A temporary variable to hold connections associated with an event
    xtcp_connection_t conn;
    
    select {
      // Respond to an event from the tcp server
      case i_xtcp.packet_ready(): {
        i_xtcp.get_packet(conn, rx_tmp, RX_BUFFER_SIZE, data_len);
        switch (conn.event) {
          case XTCP_IFUP:
            debug_printf("IFUP\n");
            break;

          case XTCP_IFDOWN:
            // Tidy up and close any connections we have open
            debug_printf("IFDOWN\n");
            for (int i = 0; i < OPEN_PORTS_PER_PROCESS; i++) {
              if (connection_states[i].active) {
                connection_states[i].active = 0;
                connection_states[i].conn_id = INIT_VAL;
              }
            }
            break;

          case XTCP_NEW_CONNECTION:
            int k;
            // Try and find an empty connection slot
            for (k = 0; k < OPEN_PORTS_PER_PROCESS; k++) {
              if (!connection_states[k].active) {
                break;
              }
            }

            if (k == OPEN_PORTS_PER_PROCESS) {
              debug_printf("failed conn: %d\n", conn.id);
              // If no free connection slots were found, abort the connection
              i_xtcp.abort(conn);
            } else {
              debug_printf("new conn: %d\n", conn.id);
              // Otherwise, assign the connection to a slot
              connection_states[k].active = 1;
              connection_states[k].conn_id = conn.id;
              i_xtcp.set_appstate(conn, (xtcp_appstate_t)&connection_states[k]);
            }
            break;

          case XTCP_RECV_DATA:
            for (int j = 0; j < OPEN_PORTS_PER_PROCESS; j++) {
              if (connection_states[j].conn_id == conn.id) {
                for (int i = 0; i < data_len; i++) {
                  const int reverse_i = (data_len - 1) - i;
                  tx_buffer[j][i] = rx_tmp[reverse_i];
                }
                response_lens[j] = data_len;
                i_xtcp.send(conn, tx_buffer[j], response_lens[j]);
                break;
              }
            }
            break;

          case XTCP_RESEND_DATA:
            for (int j = 0; j < OPEN_PORTS_PER_PROCESS; j++) {
              if (connection_states[j].conn_id == conn.id) {
                i_xtcp.send(conn, tx_buffer[j], response_lens[j]);
                break;
              }
            }
            break;

          case XTCP_SENT_DATA:
            // When a reponse is sent, the connection is closed opening up
            // for another new connection on the listening port
            break;

          case XTCP_TIMED_OUT:
          case XTCP_ABORTED:
          case XTCP_CLOSED:
            for (int t = 0; t < OPEN_PORTS_PER_PROCESS; t++) {
              // Slight hack to kill off process once python script finishes
              if (rx_tmp[0] == 'a') {
                exit(0);
              } else {
                debug_printf("closing (%d): %c, %c\n", conn.id, rx_tmp[0], conn.event + '0');
              }

              if (connection_states[t].conn_id == conn.id) {
                connection_states[t].active = 0;
                connection_states[t].conn_id = INIT_VAL;
                response_lens[t] = INIT_VAL;
                break;
              }
            }
            break;
        }
        break;
      }
    }
  }
}
