// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include "lwip_xtcp.h"
#include <xtcp.h>
#include <xtcp_server.h>
#include <xtcp_server_impl.h>
#include <string.h>
#include <uip_xtcp.h>
#include <smi.h>
#include "xtcp_conf_derived.h"
#include <xassert.h>
#include <print.h>
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "netif/etharp.h"
#include "lwip/autoip.h"
#include "lwip/init.h"
#include "lwip/tcp.h"
#include "lwip/tcp_impl.h"
#include "lwip/igmp.h"
#include "lwip/dhcp.h"

#define MAX_PACKET_BYTES 1518

// These pointers are used to store connections for sending in
// xcoredev.xc
extern client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx;
extern client interface mii_if * unsafe xtcp_i_mii;
extern mii_info_t xtcp_mii_info;

static void low_level_init(struct netif &netif, char mac_address[6])
{  
  /* set MAC hardware address length */
  netif.hwaddr_len = ETHARP_HWADDR_LEN;
  /* set MAC hardware address */
  memcpy(netif.hwaddr, mac_address, ETHARP_HWADDR_LEN);
  /* maximum transfer unit */
  netif.mtu = 1500;
  /* device capabilities */
  netif.flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_UP;
}

typedef enum {
  ARP_TIMEOUT = 0,
  AUTOIP_TIMEOUT,
  TCP_TIMEOUT,
  IGMP_TIMEOUT,
  DHCP_COARSE_TIMEOUT,
  DHCP_FINE_TIMEOUT,
  NUM_TIMEOUTS
} timeout_type;

static void init_timers(unsigned period[NUM_TIMEOUTS],
                        unsigned timeout[NUM_TIMEOUTS],
                        unsigned time_now)
{
  period[ARP_TIMEOUT] = ARP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[AUTOIP_TIMEOUT] = AUTOIP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[TCP_TIMEOUT] = TCP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[IGMP_TIMEOUT] = IGMP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[DHCP_COARSE_TIMEOUT] = DHCP_COARSE_TIMER_MSECS * XS1_TIMER_KHZ;
  period[DHCP_FINE_TIMEOUT] = DHCP_FINE_TIMER_MSECS * XS1_TIMER_KHZ;

  for (int i=0; i < NUM_TIMEOUTS; i++) {
    timeout[i] = time_now + period[i];
  }
}

static unsafe void process_rx_packet(char buffer[], size_t n_bytes,
  struct netif *unsafe netif)
{
  struct pbuf *unsafe p, *unsafe q;
  if (ETH_PAD_SIZE) {
    n_bytes += ETH_PAD_SIZE; /* allow room for Ethernet padding */
  }
  /* We allocate a pbuf chain of pbufs from the pool. */
  p = pbuf_alloc(PBUF_RAW, n_bytes, PBUF_POOL);

  if (p != NULL) {
    if (ETH_PAD_SIZE) {
      pbuf_header(p, -ETH_PAD_SIZE); /* drop the padding word */
    }
    /* We iterate over the pbuf chain until we have read the entire
     * packet into the pbuf. */
    unsigned byte_cnt = 0;
    for (q = p; q != NULL; q = q->next) {
      /* Read enough bytes to fill this pbuf in the chain. The
       * available data in the pbuf is given by the q->len
       * variable. */
      memcpy(q->payload, (char *unsafe)&buffer[byte_cnt], q->len);
      byte_cnt += q->len;
    }

    if (ETH_PAD_SIZE) {
      pbuf_header(p, ETH_PAD_SIZE); /* reclaim the padding word */
    }

    ethernet_input(p, netif); // Process the packet
  } else {
    debug_printf("No buffers free\n");
  }
}

void xtcp_lwip(chanend xtcp[n], size_t n,
               client mii_if ?i_mii,
               client ethernet_cfg_if ?i_eth_cfg,
               client ethernet_rx_if ?i_eth_rx,
               client ethernet_tx_if ?i_eth_tx,
               client smi_if ?i_smi,
               uint8_t phy_address,
               const char (&?mac_address0)[6],
               otp_ports_t &?otp_ports,
               xtcp_ipconfig_t &ipconfig)
{
  mii_info_t mii_info;
  timer timers[NUM_TIMEOUTS];
  unsigned timeout[NUM_TIMEOUTS];
  unsigned period[NUM_TIMEOUTS];

  char mac_address[6];
  struct netif my_netif;
  struct netif *unsafe netif;

  if (!isnull(mac_address0)) {
    memcpy(mac_address, mac_address0, 6);
  } else if (!isnull(otp_ports)) {
    otp_board_info_get_mac(otp_ports, 0, mac_address);
  } else if (!isnull(i_eth_cfg)) {
    i_eth_cfg.get_macaddr(0, mac_address);
  } else {
    fail("Must supply OTP ports or MAC address to xtcp component");
  }

  if (!isnull(i_mii)) {
    mii_info = i_mii.init();
    xtcp_mii_info = mii_info;
    unsafe {
      xtcp_i_mii = (client mii_if * unsafe) &i_mii;
    }
  }

  if (!isnull(i_eth_cfg)) {
    unsafe {
      xtcp_i_eth_tx = (client ethernet_tx_if * unsafe) &i_eth_tx;
      i_eth_cfg.set_macaddr(0, mac_address);

      size_t index = i_eth_rx.get_index();
      ethernet_macaddr_filter_t macaddr_filter;
      memcpy(macaddr_filter.addr, mac_address, sizeof(mac_address));
      i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

      // Add broadcast filter
      for (size_t i = 0; i < 6; i++)
        macaddr_filter.addr[i] = 0xff;
      i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

      // Only allow ARP and IP packets to the stack
      i_eth_cfg.add_ethertype_filter(index, 0x0806);
      i_eth_cfg.add_ethertype_filter(index, 0x0800);
    }
  }

  // uip_server_init(xtcp, n, &ipconfig, mac_address);
  xtcpd_init(xtcp, n);

  lwip_init();

  ip4_addr_t ipaddr, netmask, gateway;
  memcpy(&ipaddr, ipconfig.ipaddr, sizeof(xtcp_ipaddr_t));
  memcpy(&netmask, ipconfig.netmask, sizeof(xtcp_ipaddr_t));
  memcpy(&gateway, ipconfig.gateway, sizeof(xtcp_ipaddr_t));

  unsafe {
    netif = &my_netif;
    netif = netif_add(netif, &ipaddr, &netmask, &gateway, NULL);
    netif_set_default(netif);
  }

  low_level_init(my_netif, mac_address); // Needs to be called after netif_add which zeroes everything

  if (ipconfig.ipaddr[0] == 0) {
    if (dhcp_start(netif) != ERR_OK) fail("DHCP error");
  }
  netif_set_up(netif);

  int time_now;
  timers[0] :> time_now;
  init_timers(period, timeout, time_now);

  while (1) {
    unsafe {
    select {
    case !isnull(i_mii) => mii_incoming_packet(mii_info):
      int * unsafe data;
      do {
        int nbytes;
        unsigned timestamp;
        {data, nbytes, timestamp} = i_mii.get_incoming_packet();
        if (data) {
          process_rx_packet((char *)data, nbytes, netif);
          i_mii.release_packet(data);
        }
      } while (data != NULL);
      break;
    case !isnull(i_eth_rx) => i_eth_rx.packet_ready():
      debug_printf("select packet_ready\n");
      char buffer[MAX_PACKET_BYTES];
      ethernet_packet_info_t desc;
      i_eth_rx.get_packet(desc, (char *) buffer, MAX_PACKET_BYTES);

      if (desc.type == ETH_DATA) {
        process_rx_packet(buffer, desc.len, netif);
      }
      else if (isnull(i_smi) && desc.type == ETH_IF_STATUS) {
        if (((unsigned char *)buffer)[0] == ETHERNET_LINK_UP) {
          netif_set_link_up(netif);
          lwip_xtcp_up();
        }
        else {
          netif_set_link_down(netif);
          lwip_xtcp_down();
        }
      }
      break;

    case (int i=0;i<n;i++) xtcpd_service_client(xtcp[i], i):
      break;

    case(size_t i = 0; i < NUM_TIMEOUTS; i++)
      timers[i] when timerafter(timeout[i]) :> unsigned current:

      switch (i) {
      case ARP_TIMEOUT: {
        etharp_tmr();
        // Check for the link state
        if (!isnull(i_smi))
        {
          static int linkstate=0;
          ethernet_link_state_t status = smi_get_link_state(i_smi, phy_address);
          if (!status && linkstate) {
            if (!isnull(i_eth_cfg)) {
              i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
            }
            netif_set_link_down(netif);
            lwip_xtcp_down();
          }
          if (status && !linkstate) {
            if (!isnull(i_eth_cfg)) {
              i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
            }
            netif_set_link_up(netif);
          }
          linkstate = status;
        }

        if (!get_uip_xtcp_ifstate() && dhcp_supplied_address(netif)) {
          uint32_t ip = ip4_addr_get_u32(&netif->ip_addr);
          debug_printf("DHCP: Got %d.%d.%d.%d\n", ip4_addr1(&ip),
                                                  ip4_addr2(&ip),
                                                  ip4_addr3(&ip),
                                                  ip4_addr4(&ip));
          lwip_xtcp_up();
        }
        break;
      }
      case AUTOIP_TIMEOUT: autoip_tmr(); break;
      case TCP_TIMEOUT: tcp_tmr(); break;
      case IGMP_TIMEOUT: igmp_tmr(); break;
      case DHCP_COARSE_TIMEOUT: dhcp_coarse_tmr(); break;
      case DHCP_FINE_TIMEOUT: dhcp_fine_tmr(); break;
      default: fail("Bad timer\n"); break;
      }

      timeout[i] = current + period[i];
      uip_xtcp_checkstate();

      break;
    default:
      xtcpd_check_connection_poll();
      break;
    }
    }
  }
}
