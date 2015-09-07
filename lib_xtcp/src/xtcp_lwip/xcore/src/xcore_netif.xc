#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"

unsafe err_t xcore_igmp_mac_filter(struct netif *unsafe netif,
                                   const ip4_addr_t *unsafe group,
                                   u8_t action) {

}

err_t xcore_linkoutput(struct netif *unsafe netif, struct pbuf *unsafe p) {

}