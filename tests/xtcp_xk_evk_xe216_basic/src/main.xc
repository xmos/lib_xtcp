// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <string.h>
#include <stdlib.h>
#include <xscope.h>

#include "debug_print.h"
#include "common.h"
#include "ethernet.h"
#include "otp_board_info.h"
#include "smi.h"
#include "xk_evk_xe216/board.h"
#include "xtcp.h"

otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

port p_smi_mdio   = on tile[1]: XS1_PORT_1C;
port p_smi_mdc    = on tile[1]: XS1_PORT_1D;

// IP Config - change this to suit your network.  Leave with all 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
        { 192, 168, 210, 198 }, // ip address (eg 192,168,0,2)
        { 255, 255, 255, 0 }, // netmask (eg 255,255,255,0)
        { 0, 0, 0, 0 } // gateway (eg 192,168,0,1)
};

// Defines
#define INCOMING_PORT 15533

void xscope_user_init(void) {
  xscope_mode_lossless();
}

int main(void) {
  xtcp_if i_xtcp[REFLECT_PROCESSES];
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  streaming chan c_rgmii_cfg;
  smi_if i_smi;

  par {

    on tile[1]: rgmii_ethernet_mac(i_rx, NUM_ETH_CLIENTS,
                                         i_tx, NUM_ETH_CLIENTS,
                                         null, null,
                                         c_rgmii_cfg,
                                         rgmii_ports,
                                         ETHERNET_DISABLE_SHAPER);

    on tile[1].core[0]: rgmii_ethernet_mac_config(i_cfg, NUM_CFG_CLIENTS, c_rgmii_cfg);

    on tile[1].core[0]: xk_eth_xe216_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER]);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: xtcp_lwip(i_xtcp, REFLECT_PROCESSES, null,
                          i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                          null, otp_ports, ipconfig);

    // The simple udp reflector thread
    par (int i = 0; i < REFLECT_PROCESSES; i++) {
      on tile[0]: reflect(i_xtcp[i], INCOMING_PORT + (i * 10));
    }
  }
  return 0;
}
