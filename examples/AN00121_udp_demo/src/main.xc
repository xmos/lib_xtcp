// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#include <xs1.h>
#include <platform.h>
#include "ethernet.h"
#include "smi.h"
#include "xk_eth_xu316_dual_100m/board.h"
#include "xtcp.h"
#include "udp_reflect.h"

port p_smi_mdio = MDIO;
port p_smi_mdc = MDC;

port p_phy_rxd = PHY_0_RXD_4BIT;
port p_phy_txd = PHY_0_TXD_4BIT;
port p_phy_rxdv = PHY_0_RXDV;
port p_phy_txen = PHY_0_TX_EN;
// Set to PHY_0_CLK_50M for single PHY and PHY_1_CLK_50M for dual PHY
port p_phy_clk = PHY_0_CLK_50M;

clock phy_rxclk = on tile[0]: XS1_CLKBLK_1;
clock phy_txclk = on tile[0]: XS1_CLKBLK_2;


// An enum to manage the array of connections from the ethernet component
// to its clients.
enum eth_clients {
  ETH_TO_ICMP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_ICMP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
};

#define ETH_RX_BUFFER_SIZE_WORDS 1600

// Set to your desired IP address
static xtcp_ipconfig_t ipconfig = {
  {192, 168, 10, 178},
  {255, 255, 255, 0},
  {0, 0, 0, 0},
};
// MAC address within the XMOS block of 00:22:97:xx:xx:xx. Please adjust to your desired address.
static unsigned char mac_address_phy[MACADDR_NUM_BYTES] = {0x00, 0x22, 0x97, 0x01, 0x02, 0x03};


int main()
{
  xtcp_if i_xtcp[1];
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
                                      get_port_timings(0),
                                      ETH_RX_BUFFER_SIZE_WORDS, ETH_RX_BUFFER_SIZE_WORDS,
                                      ETHERNET_DISABLE_SHAPER);

    on tile[1]: dual_dp83826e_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER], null);
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
                    
#ifdef XTCP_STACK_LWIP
    // TCP component
    on tile[1]: xtcp_lwip(
      i_xtcp, 1, null,
      i_cfg[CFG_TO_ICMP], i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
      null, 0,
      mac_address_phy, null, ipconfig);
#elif defined( XTCP_STACK_UIP )
    // TCP component
    on tile[1]: xtcp_uip(
      i_xtcp, 1, null,
      i_cfg[CFG_TO_ICMP], i_rx[ETH_TO_ICMP], i_tx[ETH_TO_ICMP],
      null, 0,
      mac_address_phy, null, ipconfig);
#endif 

    // The simple udp reflector thread
    on tile[0]: udp_reflect(i_xtcp[0]);
  }
  return 0;
}
