// Copyright (c) 2017, XMOS Ltd, All rights reserved
#include "common.h"

void swap(char * alias a, char * alias b)
{
  const char tmp = *a;
  *a = *b;
  *b = tmp;
}

void reverse(char * buffer, int size)
{
  for (int i = 0, k = size - 1; i < k; ++i, --k) {
    swap(buffer + i, buffer + k);
  }
}

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *   - Periodically sends out a fixed packet to a broadcast IP address.
 *
 */
void udp_reflect(client xtcp_if i_xtcp, int start_port)
{
  debug_printf("start.\n");
  // A temporary variable to hold connections associated with an event
  xtcp_connection_t conn[OPEN_PORTS_PER_PROCESS];

  for (int i = 0; i < OPEN_PORTS_PER_PROCESS; ++i) {
    conn[i] = i_xtcp.socket(PROTOCOL);

    debug_printf("Listening on port: %d\n", i + start_port);
    i_xtcp.listen(conn[i], i + start_port, PROTOCOL);
  }

  int running = OPEN_PORTS_PER_PROCESS;
  int recv_count = 0;
  while (running > 0) {
    xtcp_connection_t client_conn;
    select {
      // Respond to an event from the tcp server
      case i_xtcp.event_ready():
        switch (i_xtcp.get_event(client_conn))
          {
          case XTCP_IFUP:
            debug_printf("IFUP\n");
            break;

          case XTCP_IFDOWN:
            debug_printf("IFDOWN\n");
            break;

          case XTCP_RECV_DATA:
            char buffer[RX_BUFFER_SIZE];
            recv_count += 1;
            const int recved = i_xtcp.recv(client_conn, buffer, RX_BUFFER_SIZE);
            if (recved > 0) {
              if (memcmp(buffer, "a", 1) == 0) {
                running = 0;
              } else {
                reverse(buffer, recved);
                for (int i = 0; i < recved;) {
                  const int sent = i_xtcp.send(client_conn, buffer + i, recved - i);

                  if (sent > 0 ) {
                    i += sent;
                  }
                }
              }
            }
            break;
        }
        break;
    }
  }

  debug_printf("recieved %d packets\n", recv_count);
  debug_printf("done.\n");
}
