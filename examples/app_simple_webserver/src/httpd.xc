// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#include <string.h>
#include <print.h>
#include "xtcp.h"
#include "httpd.h"

// Maximum number of concurrent connections
#define NUM_HTTPD_CONNECTIONS 10

// Maximum number of bytes to receive at once
#define RX_BUFFER_SIZE 1518


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
  i_xtcp.listen(80, XTCP_PROTOCOL_TCP);

  for (int i = 0; i < NUM_HTTPD_CONNECTIONS; i++ ) {
    connection_states[i].active = 0;
    unsafe {
      connection_states[i].dptr = NULL;
    }
  }
}

// Parses a HTTP request for a GET
void parse_http_request(httpd_state_t *hs, char *data, int len)
{
  // Default HTTP page with HTTP headers included
  static char page[] =
    "HTTP/1.0 200 OK\nServer: xc2/pre-1.0 (http://xmos.com)\nContent-type: text/html\n\n"
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
void httpd_send(client xtcp_if i_xtcp, xtcp_connection_t &conn)
{
  unsafe {
    struct httpd_state_t *hs = (struct httpd_state_t *) conn.appstate;

    // Check if we have no data to send
    if (hs->dlen == 0 || hs->dptr == NULL) {
      // Close the connection
      i_xtcp.close(conn);

    } else {
      // We need to send some new data
      int len = hs->dlen;

      if (len > conn.mss) {
        len = conn.mss;
      }

      i_xtcp.send(conn, (char*)hs->dptr, len);

      hs->prev_dptr = hs->dptr;
      hs->dptr += len;
      hs->dlen -= len;
    }
  }
}


// Receive a HTTP request
void httpd_recv(client xtcp_if i_xtcp, xtcp_connection_t &conn,
                char data[n], const unsigned n)
{
  unsafe {
    struct httpd_state_t *hs = (struct httpd_state_t *) conn.appstate;

    // If we already have data to send, return
    if (hs == NULL || hs->dptr != NULL) {
      return;
    }

    // Otherwise we have data, so parse it
    parse_http_request(hs, &data[0], n);

    httpd_send(i_xtcp, conn);
  }
}


// Setup a new connection
void httpd_init_state(client xtcp_if i_xtcp, xtcp_connection_t &conn)
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
    i_xtcp.abort(conn);
  } else {
    // Otherwise, assign the connection to a slot
    connection_states[i].active = 1;
    connection_states[i].conn_id = conn.id;
    connection_states[i].dptr = NULL;
    i_xtcp.set_appstate(conn, (xtcp_appstate_t) &connection_states[i]);
  }
}


// Free a connection slot, for a finished connection
void httpd_free_state(xtcp_connection_t &conn)
{
  for (int i = 0; i < NUM_HTTPD_CONNECTIONS; i++) {
    if (connection_states[i].conn_id == conn.id) {
      connection_states[i].active = 0;
    }
  }
}


// HTTP event handler
void xhttpd(client xtcp_if i_xtcp)
{
  printstr("**WELCOME TO THE SIMPLE WEBSERVER DEMO**\n");

  // Initiate the HTTP state
  httpd_init(i_xtcp);

  // Loop forever processing TCP events
  while(1) {
    xtcp_connection_t conn;
    char rx_buffer[RX_BUFFER_SIZE];
    unsigned data_len;

    select {
      case i_xtcp.packet_ready(): {
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, data_len);

        if (conn.local_port == 80) {
          // HTTP connections
          switch (conn.event) {
            case XTCP_NEW_CONNECTION:
              httpd_init_state(i_xtcp, conn);
              break;
            case XTCP_RECV_DATA:
              httpd_recv(i_xtcp, conn, rx_buffer, data_len);
              break;
            case XTCP_SENT_DATA:
              httpd_send(i_xtcp, conn);
              break;
            case XTCP_RESEND_DATA:
              unsafe {
                struct httpd_state_t *hs = (struct httpd_state_t *) conn.appstate;
                i_xtcp.send(conn, (char*)hs->prev_dptr, (hs->dptr - hs->prev_dptr));
              }
              break;
            case XTCP_TIMED_OUT:
            case XTCP_ABORTED:
            case XTCP_CLOSED:
                httpd_free_state(conn);
                break;
            default:
              // Ignore anything else
              break;
          }
        } else {
          // Other connections
          switch(conn.event) {
            case XTCP_IFUP:
              xtcp_ipconfig_t ipconfig;
              i_xtcp.get_ipconfig(ipconfig);

              printstr("IP Address: ");
              printint(ipconfig.ipaddr[0]);printstr(".");
              printint(ipconfig.ipaddr[1]);printstr(".");
              printint(ipconfig.ipaddr[2]);printstr(".");
              printint(ipconfig.ipaddr[3]);printstr("\n");
              break;
            default:
              break;
          }
        }
        break;
      }
    }
  }
}
