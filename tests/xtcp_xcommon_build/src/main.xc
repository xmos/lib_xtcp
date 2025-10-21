// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include "xtcp.h"
#include "httpd.h"
#include "smi.h"
#include "otp_board_info.h"
#include "xk_evk_xe216/board.h"

// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

port p_smi_mdio   = on tile[1]: XS1_PORT_1C;
port p_smi_mdc    = on tile[1]: XS1_PORT_1D;

enum xtcp_clients {
  XTCP_TO_HTTP,
  NUM_XTCP_CLIENTS
};

enum eth_clients {
  ETH_TO_XTCP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_XTCP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
};

// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP
xtcp_ipconfig_t ipconfig = {
  { 192, 168, 200, 178 }, // ip address (eg 192,168,1,178)
  { 255, 255, 255,   0 }, // netmask (eg 255,255,255,0)
  {   0,   0,   0,   0 }  // gateway (eg 192,168,0,1)
};

#define ETH_RX_BUFFER_SIZE_WORDS 1600

void xtcp_configure_mac(unsigned netif_id, uint8_t mac_address[MACADDR_NUM_BYTES]) {
  (void)netif_id;
  otp_board_info_get_mac(otp_ports, 0, mac_address);
}

int main(void) {
  xtcp_if         i_xtcp[NUM_XTCP_CLIENTS];
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if  i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if  i_tx[NUM_ETH_CLIENTS];
  smi_if          i_smi;
  streaming chan  c_rgmii_cfg;

  par {
    on tile[1]: rgmii_ethernet_mac(i_rx, NUM_ETH_CLIENTS,
                                   i_tx, NUM_ETH_CLIENTS,
                                   null, null,
                                   c_rgmii_cfg,
                                   rgmii_ports, 
                                   ETHERNET_DISABLE_SHAPER);
    on tile[1].core[0]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_CLIENTS, c_rgmii_cfg);
    on tile[1].core[0]: xk_eth_xe216_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER]);
  
    // SMI/ethernet phy driver
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    // TCP component
    on tile[0]: xtcp_lwip(i_xtcp, NUM_XTCP_CLIENTS, null,
                          i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                          ipconfig);

    // HTTP server application
    on tile[0]: xhttpd(i_xtcp[XTCP_TO_HTTP]);
  }
  return 0;
}
