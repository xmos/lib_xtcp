// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#include <print.h>
#include <xs1.h>
#include "uip_xtcp.h"
#include "xtcp_conf_derived.h"
#include <ethernet.h>
#include <mii.h>
#include <string.h>

extern unsigned short uip_len;
extern unsigned int uip_buf32[];

client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx = NULL;
client interface mii_if * unsafe xtcp_i_mii = NULL;
mii_info_t xtcp_mii_info;

#ifndef UIP_MAX_TRANSMIT_SIZE
#define UIP_MAX_TRANSMIT_SIZE 1520
#endif


unsafe static void mii_send(void)
{
#ifdef UIP_SINGLE_SERVER_DOUBLE_BUFFER_TX
  static int txbuf0[(UIP_MAX_TRANSMIT_SIZE+3)/4];
  static int txbuf1[(UIP_MAX_TRANSMIT_SIZE+3)/4];
  static int tx_buf_in_use=0;
  static int n=0;
  int len = uip_len;
  unsigned nWords;
  if (len<60) {
    for (int i=len;i<60;i++)
      (uip_buf32, unsigned char[])[i] = 0;
    len=60;
  }
  nWords = (len+3)>>2;

  if (len > UIP_MAX_TRANSMIT_SIZE) {
#ifdef UIP_DEBUG_MAX_TRANSMIT_SIZE
    printstr("Error: Trying to send too big a packet: ");
    printint(len);
    printstr(" bytes.\n");
#endif
    return;
  }
  switch (n) {
  case 0:
    memcpy(txbuf0, uip_buf32, len);
    if (tx_buf_in_use) {
      select {
      case mii_packet_sent(xtcp_mii_info):
        break;
      }
    }
    xtcp_i_mii->send_packet(txbuf0, len);
    n = 1;
    break;
  case 1:
    memcpy(txbuf1, uip_buf32, len);
    if (tx_buf_in_use) {
      select {
      case mii_packet_sent(xtcp_mii_info):
        break;
      }
    }
    xtcp_i_mii->send_packet(txbuf1, len);
    n = 0;
    break;
  }
  tx_buf_in_use=1;
#else
  static int txbuf[(UIP_MAX_TRANSMIT_SIZE+3)/4];
  static int tx_buf_in_use=0;
  unsigned nWords;
  int len=uip_len;
  if (tx_buf_in_use) {
    select {
    case mii_packet_sent(xtcp_mii_info):
      break;
    }
  }
  if (len<60) {
    for (int i=len;i<60;i++)
      (uip_buf32, unsigned char[])[i] = 0;
    len=60;
  }
  nWords = (len+3)>>2;
  memcpy(txbuf, uip_buf32, len);
  xtcp_i_mii->send_packet(txbuf, len);
  tx_buf_in_use=1;
#endif
}

void
xcoredev_send(void)
{
  int len = uip_len;
  if (len != 0) {
    if (len < 64)  {
      for (int i=len;i<64;i++)
        (uip_buf32, unsigned char[])[i] = 0;
      len=64;
    }
    unsafe {
      if (xtcp_i_eth_tx != NULL) {
        xtcp_i_eth_tx->send_packet((char *) uip_buf32, len,
                                   ETHERNET_ALL_INTERFACES);
      } else {
        mii_send();
      }
    }
  }
}