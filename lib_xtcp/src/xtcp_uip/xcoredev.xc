// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <print.h>
#include <xs1.h>
#include <ethernet.h>
#include <mii.h>
#include <string.h>
#include "xcoredev.h"

extern unsigned short uip_len;
extern unsigned char * unsafe uip_buf;
extern void * unsafe uip_sappdata;

client interface ethernet_tx_if unsafe xtcp_i_eth_tx_uip;
client interface mii_if unsafe xtcp_i_mii_uip;
mii_info_t xtcp_mii_info_uip;
enum xcoredev_eth_e xcoredev_eth = XCORE_ETH_NONE;

#ifndef UIP_MAX_TRANSMIT_SIZE
#define UIP_MAX_TRANSMIT_SIZE 1520 /* bytes */
#endif

unsafe static void 
mii_send(void)
{
  static int txbuf[(UIP_MAX_TRANSMIT_SIZE+3)/4];
  static int first_packet_sent = 0;
  int len = uip_len;
  
  if (first_packet_sent) {
    select {
    case mii_packet_sent(xtcp_mii_info_uip):
      break;
    }
  }
  
  if (len < 60) {
    for (int i=len; i < 60; i++) {
      uip_buf[i] = 0;
    }
    len=60;
  }

  memcpy(txbuf, uip_buf, len);
  xtcp_i_mii_uip.send_packet(txbuf, len);
  first_packet_sent=1;
}

void
xcoredev_send(void)
{
  unsafe {
    int len = uip_len;
    if (len != 0) {
      if (xcoredev_eth == XCORE_ETH_TX) {
        if (len < 60) {
          for (int i=len; i<60; i++) {
            uip_buf[i] = 0;
          }
          len=60;
        }
        ((client interface ethernet_tx_if)xtcp_i_eth_tx_uip).send_packet((char *) uip_buf, len, ETHERNET_ALL_INTERFACES);
      } else if (xcoredev_eth == XCORE_ETH_MII) {
        mii_send();
      }
    }
  }
}