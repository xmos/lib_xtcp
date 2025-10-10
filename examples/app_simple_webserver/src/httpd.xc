// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <string.h>

#include "debug_print.h"
#include "xtcp.h"
#include "httpd.h"

// Maximum number of concurrent connections
#define NUM_HTTPD_CONNECTIONS 10

// Maximum number of bytes to receive at once
#define RX_BUFFER_SIZE 1518

static const xtcp_ipaddr_t any_addr = {0, 0, 0, 0};

// Structure to hold HTTP state
typedef struct httpd_state_t {
  int active;                //< Whether this state structure is being used
                             //  for a connection
  int conn_id;               //< The connection id
  char * unsafe dptr;        //< Pointer to the remaining data to send
  int dlen;                  //< The length of remaining data to send
  char * unsafe prev_dptr;   //< Pointer to the previously sent item of data
} httpd_state_t;

httpd_state_t connection_states[NUM_HTTPD_CONNECTIONS];

// Initialize the HTTP state
void httpd_init(client xtcp_if i_xtcp)
{
  // Listen on the http port
  int32_t listening_connection = i_xtcp.socket(XTCP_PROTOCOL_TCP);
  int32_t listen_result = i_xtcp.listen(listening_connection, 80, any_addr);  
  if (listen_result < 0) {
    debug_printf("Failed to listen on port %d, %i\n", 80, listen_result);
  } else {
    debug_printf("Listening on port %d, id %d\n", 80, listening_connection);
  }

  for (int i = 0; i < NUM_HTTPD_CONNECTIONS; i++ ) {
    connection_states[i].active = 0;
    connection_states[i].conn_id = -1;
    unsafe {
      connection_states[i].dptr = NULL;
    }
  }
}

// Parses a HTTP request for a GET
void parse_http_request(httpd_state_t *hs, char *data, int len)
{
  (void) len;

  // Default HTTP page with HTTP headers included
  static char page[] =
    "HTTP/1.1 200 OK\n"
    "Server: xc2/pre-1.0 (http://xmos.com)\n"
    "Connection: close\n"
    "Content-Length: 94\n"
    "Content-type: text/html\n\n"
    "<!DOCTYPE html>\n"
    "<html><head><title>Hello world</title></head>\n"
    "<body>Hello World!</body></html>";

  // Return if we have data already
  if (hs->dptr != NULL) {
    return;
  }

  // Test if we received a HTTP GET request
  if (strncmp(data, "GET ", 4) == 0) {
    // Assign the default page character array as the data to send
    unsafe {
      hs->dptr = &page[0];
    }
    hs->dlen = strlen(&page[0]);
  } else {
    // We did not receive a get request, so do nothing
  }
}


// Send some data back for a HTTP request
void httpd_send(client xtcp_if i_xtcp, int32_t conn_id)
{
  unsafe {
    struct httpd_state_t *hs = (struct httpd_state_t *)i_xtcp.get_connection_client_data(conn_id);

    // Check if we have no data to send
    if (hs->dlen == 0 || hs->dptr == NULL) {
      debug_printf("All data sent, id %d\n", conn_id);

    } else {
      // We need to send some new data
      int len = hs->dlen;

      debug_printf("Sending %d bytes\n", len);
      int32_t result = i_xtcp.send(conn_id, (char*)hs->dptr, len);
      if (result < 0) {
        debug_printf("Error sending data: %d\n", result);
        // Close the connection
        i_xtcp.close(conn_id);
        return;
      }

      hs->prev_dptr = hs->dptr;
      hs->dptr += len;
      hs->dlen -= len;
    }
  }
}


// Receive a HTTP request
void httpd_recv(client xtcp_if i_xtcp, int32_t conn_id,
                char data[n], const unsigned n)
{
  unsafe {
    struct httpd_state_t *hs = (struct httpd_state_t *)i_xtcp.get_connection_client_data(conn_id);

    // If we already have data to send, return
    if (hs == NULL || hs->dptr != NULL) {
      return;
    }

    // Otherwise we have data, so parse it
    parse_http_request(hs, &data[0], n);

    httpd_send(i_xtcp, conn_id);
  }
}


// Setup a new connection
void httpd_init_state(client xtcp_if i_xtcp, int32_t conn_id)
{
  int i;

  // Try and find an empty connection slot
  for (i = 0; i < NUM_HTTPD_CONNECTIONS; i++) {
    if (!connection_states[i].active) {
      break;
    }
  }

  // If no free connection slots were found, abort the connection
  if (i == NUM_HTTPD_CONNECTIONS) {
    i_xtcp.abort(conn_id);
    debug_printf("Abort\n");
  } else {
    xtcp_remote_t remote = i_xtcp.get_ipconfig_remote(conn_id);
    debug_printf("Connection, id %d, from %d.%d.%d.%d:%d\n", conn_id,
                 remote.ipaddr[0], remote.ipaddr[1],
                 remote.ipaddr[2], remote.ipaddr[3],
                 remote.port_number);
    // Otherwise, assign the connection to a slot
    connection_states[i].active = 1;
    connection_states[i].conn_id = conn_id;
    connection_states[i].dptr = NULL;
    unsafe {
      (void)i_xtcp.set_connection_client_data(conn_id, &connection_states[i]);
    }
  }
}


// Free a connection slot, for a finished connection
void httpd_free_state(int32_t conn_id)
{
  for (int i = 0; i < NUM_HTTPD_CONNECTIONS; i++) {
    if (connection_states[i].conn_id == conn_id) {
      connection_states[i].active = 0;
      connection_states[i].conn_id = -1;
    }
  }
}


// HTTP event handler
void xhttpd(client xtcp_if i_xtcp)
{
  debug_printf("**WELCOME TO THE SIMPLE WEBSERVER DEMO**\n");

  // Initiate the HTTP state
  httpd_init(i_xtcp);

  // Loop forever processing TCP events
  while(1) {
    char rx_buffer[RX_BUFFER_SIZE];
    unsigned data_len;
    int32_t conn_id;

    select {
      case i_xtcp.event_ready():
        const xtcp_event_type_t event = i_xtcp.get_event(conn_id);
        switch (event) {
          case XTCP_EVENT_NONE:
            // No event to process
            break;
          
          case XTCP_IFUP:
            xtcp_ipconfig_t ipconfig = i_xtcp.get_netif_ipconfig(0);

            debug_printf("IP Address: %d.%d.%d.%d\n", ipconfig.ipaddr[0], ipconfig.ipaddr[1], ipconfig.ipaddr[2], ipconfig.ipaddr[3]);
            break;

          case XTCP_IFDOWN:
            debug_printf("IFDOWN\n");
            break;

          case XTCP_ACCEPTED:
            httpd_init_state(i_xtcp, conn_id);
            break;

          case XTCP_RECV_DATA:
            int32_t data_len = i_xtcp.recv(conn_id, rx_buffer, RX_BUFFER_SIZE);
            if (data_len < 0) {
              // Close connection if error receiving data
              debug_printf("RECV error: closing, id %d\n", conn_id);
              i_xtcp.close(conn_id);
              break;
            } else {
              httpd_recv(i_xtcp, conn_id, rx_buffer, data_len);
              break;
            }
            break;

          case XTCP_SENT_DATA:
            httpd_send(i_xtcp, conn_id);
            break;

          case XTCP_RESEND_DATA:
            debug_printf("Resend, id %d\n", conn_id);
            unsafe {
              struct httpd_state_t *hs = (struct httpd_state_t *)i_xtcp.get_connection_client_data(conn_id);
              i_xtcp.send(conn_id, (char*)hs->prev_dptr, (hs->dptr - hs->prev_dptr));
            }
            break;

          case XTCP_CLOSED:
            i_xtcp.close(conn_id);
            httpd_free_state(conn_id);
            debug_printf("Closed, id %d\n", conn_id);
            break;

          case XTCP_ABORTED:
            httpd_free_state(conn_id);
            debug_printf("Aborted, id %d\n", conn_id);
            break;
        }
        break;
    }
  }
}
