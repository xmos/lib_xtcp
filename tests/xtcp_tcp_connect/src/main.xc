// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <xs1.h>
#include <platform.h>
#include <xscope.h>

#include "app_tcp_connect.h"
#include "ethernet.h"
#include "smi.h"
#include "xk_eth_xu316_dual_100m/board.h"
#include "xtcp.h"


port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

port p_phy_rxd = PHY_0_RXD_4BIT;
port p_phy_txd = PHY_0_TXD_4BIT;
port p_phy_rxdv = PHY_0_RXDV;
port p_phy_txen = PHY_0_TX_EN;
// Set to PHY_0_CLK_50M when single PHY present and PHY_1_CLK_50M when dual PHY present
// For single PHY operation, check that R23 is fitted and R3 not fitted.
#ifdef XCORE_AI_MULTI_PHY_SINGLE_PHY
port p_phy_clk = PHY_0_CLK_50M;
#else
port p_phy_clk = PHY_1_CLK_50M;
#endif

clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy_txclk = on tile[0]: XS1_CLKBLK_2;

enum tcp_clients {
  TCP_TO_APP_TCP,
  NUM_TCP_CLIENTS
};

enum eth_clients {
  ETH_TO_TCP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_TCP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
};

#define ETH_RX_BUFFER_SIZE_WORDS 592

// Set to your desired IP address
static xtcp_ipconfig_t ipconfig = {
  {192, 168, 200, 188},  /* IP address, 0 for DHCP */
  {255, 255, 255,   0},  /* submask, 0 for DHCP */
  {0, 0, 0, 0},          /* Gateway */
};
// MAC address within the XMOS block of 00:22:97:xx:xx:xx. Please adjust to your desired address.
static const unsigned char mac_address_phy[MACADDR_NUM_BYTES] = {0x00, 0x22, 0x97, 0x01, 0x02, 0x33};

void xscope_user_init(void) {
  xscope_mode_lossless();
}

int main()
{
  // xtcp_if i_xtcp[NUM_TCP_CLIENTS];
  ethernet_cfg_if i_cfg[NUM_CFG_CLIENTS];
  ethernet_rx_if i_rx[NUM_ETH_CLIENTS];
  ethernet_tx_if i_tx[NUM_ETH_CLIENTS];
  smi_if i_smi;
  xtcp_if i_xtcp[NUM_TCP_CLIENTS];

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
                                      get_port_timings(DUAL_PHY_MOUNTED_PHY0),
                                      ETH_RX_BUFFER_SIZE_WORDS, ETH_RX_BUFFER_SIZE_WORDS,
                                      ETHERNET_DISABLE_SHAPER);

    on tile[1]: dual_dp83826e_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], null);
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
                    
    // TCP component
    on tile[1]: xtcp_lwip(i_xtcp, NUM_TCP_CLIENTS,
                          null, // mii_if
                          i_cfg[CFG_TO_TCP], i_rx[ETH_TO_TCP], i_tx[ETH_TO_TCP],
                          mac_address_phy, null, ipconfig);

    on tile[1]: app_tcp_connect(i_xtcp[TCP_TO_APP_TCP]);
  }
  return 0;
}
