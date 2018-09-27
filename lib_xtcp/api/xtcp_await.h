#ifndef _XTCP_AWAIT_H_
#define _XTCP_AWAIT_H_

#include "xtcp.h"

extends client interface xtcp_if : {
  void await_ifup(client xtcp_if self);

  xtcp_connection_t await_connect(client xtcp_if self, xtcp_ipaddr_t & ip_address, uint16_t ip_port);

  int await_recv(client xtcp_if self, xtcp_connection_t &conn, char buffer[], unsigned int length);

  int await_send(client xtcp_if self, xtcp_connection_t &conn, char buffer[], unsigned int length);
};

#endif
