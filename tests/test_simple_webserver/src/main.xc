// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <platform.h>
#include "xtcp.h"
#include "xhttpd.h"
#include "smi.h"
#include "otp_board_info.h"

port p_eth_rxclk  = on tile[1]: XS1_PORT_1J;
port p_eth_rxd    = on tile[1]: XS1_PORT_4E;
port p_eth_txd    = on tile[1]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1K;
port p_eth_txen   = on tile[1]: XS1_PORT_1L;
port p_eth_txclk  = on tile[1]: XS1_PORT_1I;
port p_eth_int    = on tile[1]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1P;
port p_eth_timing = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdc = on tile[1]: XS1_PORT_1N;
port p_smi_mdio = on tile[1]: XS1_PORT_1M;

otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

#if IPV6
xtcp_ipconfig_t ipconfig = {
  0,
  {{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
  {{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
  {{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}},
};
#else
// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP
xtcp_ipconfig_t ipconfig = {
  { 0, 0, 0, 0 }, // ip address (eg 192,168,0,2)
  { 0, 0, 0, 0 }, // netmask (eg 255,255,255,0)
  { 0, 0, 0, 0 }  // gateway (eg 192,168,0,1)
};
#endif

#define NUM_HTTP_CONNECTIONS (10)

#define XTCP_MII_BUFSIZE 4096

int main(void) {
  chan c_xtcp[1];

#if USE_MAC
  ethernet_cfg_if i_cfg[1];
  ethernet_rx_if i_rx[1];
  ethernet_tx_if i_tx[1];
#else
  mii_if i_mii;
#endif
  smi_if i_smi;
  par {

#if USE_MAC
    on tile[1]: mii_ethernet_mac(i_cfg, 1, i_rx, 1, i_tx, 1,
                                 p_eth_rxclk, p_eth_rxerr,
                                 p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen,
                                 p_eth_txd, p_eth_timing,
                                 eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);

    on tile[1]: xtcp(c_xtcp, 1, null,
                     i_cfg[0], i_rx[0], i_tx[0],
                     i_smi, 0, 
                     null, otp_ports, ipconfig);

#else
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);

    on tile[1]: xtcp(c_xtcp, 1, i_mii,
                     null, null, null,
                     i_smi, 0,
                     null, otp_ports, ipconfig);
#endif

    // SMI/ethernet phy driver
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);


    // HTTP server application
    on tile[1]: xhttpd(c_xtcp[0]);

  }
  return 0;
}
