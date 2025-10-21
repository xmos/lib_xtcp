// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include <string.h>
#include <stdlib.h>
#include <xscope.h>

#include "debug_print.h"
#include "common.h"
#include "ethernet.h"
#include "smi.h"
#include "xk_eth_316_dual/board.h"
#include "xtcp.h"

port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

port p_phy_rxd = RMII_PHY_0_RXD_4BIT;
port p_phy_txd = RMII_PHY_0_TXD_4BIT;
port p_phy_rxdv = RMII_PHY_0_RXDV;
port p_phy_txen = RMII_PHY_0_TX_EN;

port p_phy_clk = RMII_PHY_CLK_50M;

clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy_txclk = on tile[0]: XS1_CLKBLK_2;

// IP Config - change this to suit your network.  Leave with all 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
        { 192, 168, 200, 198 }, // ip address (eg 192,168,0,2)
        { 255, 255, 255, 0 }, // netmask (eg 255,255,255,0)
        { 0, 0, 0, 0 } // gateway (eg 192,168,0,1)
};
// MAC address within the XMOS block of 00:22:97:xx:xx:xx. Please adjust to your desired address.
static const unsigned char mac_address_phy[MACADDR_NUM_BYTES] = {0x00, 0x22, 0x97, 0x01, 0x02, 0x03};

#define ETH_RX_BUFFER_SIZE_WORDS 1600

void xscope_user_init(void) {
  xscope_mode_lossless();
}

int main(void) {
  xtcp_if i_xtcp[REFLECT_PROCESSES];
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;

  par {
    on tile[0]: rmii_ethernet_rt_mac( i_cfg, NUM_CFG_CLIENTS,
                                      i_rx, NUM_ETH_CLIENTS,
                                      i_tx, NUM_ETH_CLIENTS,
                                      null, null,
                                      p_phy_clk,
                                      p_phy_rxd,
                                      null,
                                      USE_UPPER_2B,
                                      p_phy_rxdv,
                                      p_phy_txen,
                                      p_phy_txd,
                                      null,
                                      USE_UPPER_2B,
                                      phy_rxclk,
                                      phy_txclk,
                                      get_port_timings(PHY0_PORT_TIMINGS),
                                      ETH_RX_BUFFER_SIZE_WORDS, ETH_RX_BUFFER_SIZE_WORDS,
                                      ETHERNET_DISABLE_SHAPER);

    on tile[1]: dual_ethernet_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], null);
  
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
                    
    // TCP component
    on tile[0]: xtcp_lwip(i_xtcp, REFLECT_PROCESSES,
                          null, // mii_if
                          i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                          mac_address_phy, null, ipconfig);
    
    // The simple udp reflector thread
    par (int i = 0; i < REFLECT_PROCESSES; i++) {
      on tile[0]: reflect(i_xtcp[i], INCOMING_PORT + (i * 10));
    }
  }
  return 0;
}
