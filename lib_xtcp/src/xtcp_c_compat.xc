#include "xtcp.h"
#include <string.h>

unsafe int xtcp_wait_for_ifup(client interface xtcp_if i_xtcp)
{
  int up = 0;

  while(!up) {
    up = i_xtcp.is_ifup();
  }

  return up;
}

unsafe xtcp_connection_t xtcp_socket(client interface xtcp_if i_xtcp, xtcp_protocol_t protocol)
{
  return i_xtcp.socket(protocol);
}

unsafe int xtcp_get_host_by_name(client interface xtcp_if i_xtcp, const char name[], xtcp_ipaddr_t addr)
{
  i_xtcp.request_host_by_name(name, strlen(name));

  return 0;
}

unsafe int xtcp_read(client interface xtcp_if i_xtcp, xtcp_connection_t * unsafe conn, char buffer[], const unsigned n)
{
  return i_xtcp.recv(*conn, buffer, n);
}

unsafe int xtcp_write(client interface xtcp_if i_xtcp, xtcp_connection_t * unsafe conn, char buffer[], const unsigned n)
{
  return i_xtcp.send(*conn, buffer, n);
}

unsafe int xtcp_close(client interface xtcp_if i_xtcp, xtcp_connection_t * unsafe conn)
{
  i_xtcp.close(*conn);

  return 1;
}

unsafe int xtcp_connect(client interface xtcp_if i_xtcp, xtcp_connection_t * unsafe conn, unsigned short port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol)
{
  return i_xtcp.connect(*conn, port_number, ipaddr);
}

unsafe int xtcp_wait_for_connection(client interface xtcp_if i_xtcp, xtcp_connection_t * unsafe conn)
{
  int connected = 0;
  while(!connected) {
    select {
      case i_xtcp.event_ready():
        xtcp_connection_t tmp;
        switch(i_xtcp.get_event(tmp)) {
          case 2:// case XTCP_CONNECTED:
            connected = (tmp.id == conn->id);
            break;
        }
        break;
    }
  }

  return connected;
}
