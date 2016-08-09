// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#include "xtcp.h"
#include "debug_print.h"
#include <string.h>
#include "xassert.h"

void xtcp_wait_for_ifup(chanend tcp_svr)
{
  xtcp_connection_t conn;
  conn.event = XTCP_ALREADY_HANDLED;
  do {
    slave xtcp_event(tcp_svr, conn);
  } while (conn.event != XTCP_IFUP);
  return;
}

xtcp_connection_t xtcp_wait_for_connection(chanend tcp_svr)
{
  xtcp_connection_t conn;
  conn.event = XTCP_ALREADY_HANDLED;
  do {
    slave xtcp_event(tcp_svr, conn);
  } while (conn.event != XTCP_NEW_CONNECTION);
  return conn;
}

void xtcp_wait_for_closed(chanend tcp_svr)
{
  xtcp_connection_t conn;
  conn.event = XTCP_ALREADY_HANDLED;
  do {
    slave xtcp_event(tcp_svr, conn);
  } while (conn.event != XTCP_CLOSED);
  return;
}

void xtcp_get_host_by_name(chanend tcp_svr, const char hostname[], xtcp_ipaddr_t &ipaddr)
{
  xtcp_connection_t conn;
  xtcp_request_host_by_name(tcp_svr, hostname);
  do {
    slave xtcp_event(tcp_svr, conn);
  } while (conn.event != XTCP_DNS_RESULT);

  memcpy(ipaddr, conn.remote_addr, sizeof(xtcp_ipaddr_t));
}

int xtcp_write(chanend tcp_svr,
               xtcp_connection_t &conn,
               unsigned char buf[],
               int len)
{
  int finished = 0;
  int success = len;
  int index = 0, prev = 0;
  int id = conn.id;

  xtcp_init_send(tcp_svr, conn);
  while (!finished) {
    slave xtcp_event(tcp_svr, conn);
    switch (conn.event)
      {
      case XTCP_NEW_CONNECTION:
        xtcp_close(tcp_svr, conn);
        break;
      case XTCP_REQUEST_DATA:
      case XTCP_SENT_DATA:
        {
          int sendlen = len;

          if (sendlen > conn.mss)
            sendlen = conn.mss;

          xtcp_send(tcp_svr, buf, len);
          finished = 1;
        }
        break;
      case XTCP_RESEND_DATA:
        xtcp_sendi(tcp_svr, buf, prev, (index-prev));
        break;
      case XTCP_RECV_DATA:
        fail("Received while writing");
        slave { tcp_svr <: 0; } // delay packet receive
        finished = 1;
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        if (conn.id == id) {
          finished = 1;
          success = 0;
          fail("Closed during write");
        }
        break;
      case XTCP_IFDOWN:
        finished = 1;
        success = 0;
        fail("IF down during write");
        break;
      }
  }
  return success;
}


int xtcp_read(chanend tcp_svr,
              xtcp_connection_t &conn,
              unsigned char buf[],
              int minlen)
{
  int rlen = 0;
  int id = conn.id;
  while (rlen < minlen) {
    slave xtcp_event(tcp_svr, conn);
    switch (conn.event)
      {
      case XTCP_NEW_CONNECTION:
        fail("New connection during read");
        xtcp_close(tcp_svr, conn);
        break;
      case XTCP_RECV_DATA:
        {
          int n;
          n = xtcp_recvi(tcp_svr, buf, rlen);
          rlen += n;
        }
        break;
      case XTCP_REQUEST_DATA:
      case XTCP_SENT_DATA:
      case XTCP_RESEND_DATA:
        xtcp_send(tcp_svr, null, 0);
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        if (conn.id == id) {
          return -1;
        }
        break;
      case XTCP_IFDOWN:
        return -1;
      }
  }
  return rlen;
}

