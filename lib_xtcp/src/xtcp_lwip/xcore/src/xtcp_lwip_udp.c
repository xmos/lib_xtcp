// // Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
// #include "lwip/autoip.h"
// #include "lwip/init.h"
// #include "lwip/tcp.h"
// #include "lwip/igmp.h"
// #include "lwip/dhcp.h"
// #include "lwip/udp.h"
// #include "lwip/dns.h"
// #include "xtcp_server.h"
// #include "xtcp_server_impl.h"

// extern chanend *xtcp_links;
// extern int xtcp_num;

// void xtcpd_init_state(xtcpd_state_t *s,
//                       xtcp_protocol_t protocol,
//                       xtcp_ipaddr_t remote_addr,
//                       int local_port,
//                       int remote_port,
//                       void *conn);

// void xtcpd_event(xtcp_event_type_t event,
//                  xtcpd_state_t *s);

// // void udp_recv_event(void *arg, struct udp_pcb *pcb, struct pbuf *p,
// //                     const ip_addr_t *addr, u16_t port) {
// //   switch (port) {
// //   case DHCP_CLIENT_PORT:
// //   case DHCP_SERVER_PORT:
// //     dhcp_recv(arg, pcb, p, addr, port);
// //     break;
// //   case DNS_SERVER_PORT:
// //     dns_recv(arg, pcb, p, addr, port);
// //     break;
// //   default:
// //     if (pcb == NULL) {
// //       pbuf_free(p);
// //       break;
// //     }

// //     xtcpd_state_t *s = &(pcb->xtcp_state);

// //     if ((pcb->flags & UDP_FLAGS_CONNECTED) == 0) {
// //       udp_connect(pcb, addr, port);
// //       xtcpd_init_state(s,
// //                        XTCP_PROTOCOL_UDP,
// //                        (unsigned char *) &pcb->remote_ip,
// //                        pcb->local_port,
// //                        pcb->remote_port,
// //                        pcb);
// //       xtcpd_event(XTCP_NEW_CONNECTION, s);
// //     }

// //     if (p != NULL) {
// //       if (s->linknum != -1) {
// //         xtcpd_service_clients_until_ready(s->linknum, xtcp_links, xtcp_num);
// //         xtcpd_recv_lwip_pbuf(xtcp_links, s->linknum, xtcp_num, s, p);
// //         pbuf_free(p);
// //       }
// //     }
// //     break;
// //   }
// // }