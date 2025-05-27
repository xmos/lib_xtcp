// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __XCORE_NETIF_H__
#define __XCORE_NETIF_H__
#include <xccompat.h>
#include <xc2compat.h>

enum xcore_netif_eth_e {
    XCORE_NETIF_ETH_NONE,
    XCORE_NETIF_ETH_MII,
    XCORE_NETIF_ETH_TX,
};

unsafe err_t xcore_igmp_mac_filter(struct netif *unsafe netif,
                                   const ip4_addr_t *unsafe group,
                                   u8_t action);


/** Function prototype for netif->linkoutput functions. Only used for ethernet
 * netifs. This function is called by ARP when a packet shall be sent.
 *
 * @param netif The netif which shall send a packet
 * @param p The packet to send (raw ethernet packet)
 */
err_t xcore_linkoutput(struct netif *unsafe netif, struct pbuf *unsafe p);

#endif