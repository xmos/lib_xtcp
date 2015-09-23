#include "lwip/autoip.h"
#include "lwip/init.h"
#include "lwip/tcp.h"
#include "lwip/igmp.h"
#include "lwip/dhcp.h"
#include "lwip/udp.h"
#include "lwip/dns.h"

void udp_recv_event(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                    const ip_addr_t *addr, u16_t port) {
  switch (port) 
  {
  case DHCP_CLIENT_PORT:
  case DHCP_SERVER_PORT:
    dhcp_recv(arg, pcb, p, addr, port);
    break;
  case DNS_SERVER_PORT:
    dns_recv(arg, pcb, p, addr, port);
    break;
  default:
    pbuf_free(p);
    break;
  }
}