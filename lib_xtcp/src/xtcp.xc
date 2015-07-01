// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include <xtcp.h>
#include <xtcp_server.h>
#include <xtcp_server_impl.h>
#include <string.h>
#include <uip_xtcp.h>
#include <smi.h>
#include "xtcp_conf_derived.h"
#include <xassert.h>
#include <print.h>

#define UIP_IPH_LEN    20    /* Size of IP header */
#define UIP_UDPH_LEN    8    /* Size of UDP header */
#define UIP_TCPH_LEN   20    /* Size of TCP header */
#define UIP_IPUDPH_LEN (UIP_UDPH_LEN + UIP_IPH_LEN)    /* Size of IP +
							  UDP
							  header */
#define UIP_IPTCPH_LEN (UIP_TCPH_LEN + UIP_IPH_LEN)    /* Size of IP +
							  TCP
							  header */
#define UIP_TCPIP_HLEN UIP_IPTCPH_LEN

#define UIP_LLH_LEN     14

#define UIP_BUFSIZE     (XTCP_CLIENT_BUF_SIZE + UIP_LLH_LEN + UIP_TCPIP_HLEN)

#ifndef UIP_USE_AUTOIP
#define UIP_USE_AUTOIP 1
#endif

extern "C" {
extern void uip_server_init(chanend xtcp[], int num_xtcp,
                            xtcp_ipconfig_t* ipconfig,
                            unsigned char mac_address[6]);
}

// Global variables from uip_server_support
extern unsigned short uip_len;
extern unsigned int uip_buf32[];

// Global functions from the uip stack
extern void uip_arp_timer(void);
extern void autoip_periodic();
extern void igmp_periodic();

extern void xtcpd_check_connection_poll(void);
extern void xtcp_tx_buffer(void);
extern void xtcp_process_incoming_packet(int length);
extern void xtcp_process_udp_acks(void);
extern void xtcp_process_periodic_timer(void);


// These pointers are used to store connections for sending in
// xcoredev.xc
extern client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx;
extern client interface mii_if * unsafe xtcp_i_mii;
extern mii_info_t xtcp_mii_info;

void xtcp(chanend xtcp[n], size_t n,
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
  timer tmr;
  unsigned timeout;
  unsigned arp_timer=0;
  unsigned autoip_timer=0;
  char mac_address[6];

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

  uip_server_init(xtcp, n, &ipconfig, mac_address);

  tmr :> timeout;
  timeout += 10000000;

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
          static unsigned pcnt=1;
          if (nbytes <= UIP_BUFSIZE) {
            memcpy(uip_buf32, data, nbytes);
            xtcp_process_incoming_packet(nbytes);
          }
          i_mii.release_packet(data);
        }
      } while (data != NULL);
      break;
    case !isnull(i_eth_rx) => i_eth_rx.packet_ready():
      ethernet_packet_info_t desc;
      i_eth_rx.get_packet(desc, (char *) uip_buf32, UIP_BUFSIZE);
      if (desc.type == ETH_DATA) {
        xtcp_process_incoming_packet(desc.len);
      }
      else if (isnull(i_smi) && desc.type == ETH_IF_STATUS) {
        if (((unsigned char *)uip_buf32)[0] == ETHERNET_LINK_UP) {
          uip_linkup();
        }
        else {
          uip_linkdown();
        }
      }
      break;
    case tmr when timerafter(timeout) :> timeout:
      timeout += 10000000;

      xtcpd_service_clients(xtcp, n);
      xtcpd_check_connection_poll();
      uip_xtcp_checkstate();
      xtcp_process_udp_acks();

      // Check for the link state
      if (!isnull(i_smi))
      {
        static int linkstate=0;
        ethernet_link_state_t status = smi_get_link_state(i_smi, phy_address);
        if (!status && linkstate) {
          if (!isnull(i_eth_cfg)) {
            i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
          }
          uip_linkdown();
        }
        if (status && !linkstate) {
          if (!isnull(i_eth_cfg)) {
            i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
          }
          uip_linkup();
        }
        linkstate = status;
      }

      if (++arp_timer == 100) {
        arp_timer=0;
        uip_arp_timer();
      }

      if (UIP_USE_AUTOIP) {
        if (++autoip_timer == 5) {
          autoip_timer = 0;
          autoip_periodic();
          if (uip_len > 0) {
            xtcp_tx_buffer();
          }
        }
      }

      xtcp_process_periodic_timer();
      break;
    }
    }
  }
}
