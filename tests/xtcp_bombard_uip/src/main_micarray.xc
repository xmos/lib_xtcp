// Copyright (c) 2017, XMOS Ltd, All rights reserved
#include "common.h"

#if MIC_ARRAY

// Microphone array reference design
port p_eth_rxclk  = on tile[1]: XS1_PORT_1A;
port p_eth_rxd    = on tile[1]: XS1_PORT_4A;
port p_eth_txd    = on tile[1]: XS1_PORT_4B;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1C;
port p_eth_txen   = on tile[1]: XS1_PORT_1D;
port p_eth_txclk  = on tile[1]: XS1_PORT_1B;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1K;
port p_eth_timing = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

// SMI
port p_smi        = on tile[1]: XS1_PORT_4C; // Bit 0: MDC, Bit 1: MDIO

// OTP
otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

port p_rst_shared = on tile[1]: XS1_PORT_4F; // Bit 0: DAC_RST_N, Bit 1: ETH_RST_N

xtcp_ipconfig_t ipconfig = {
        { 192, 168,   1, 197 }, // ip address (eg 192,168,0,2)
        { 255, 255, 255,   0 }, // netmask    (eg 255,255,255,0)
        {   0,   0,   0,   0 }  // gateway    (eg 192,168,0,1)
};

int main(void) {
  xtcp_if i_xtcp[REFLECT_PROCESSES];
#if RAW
  mii_if i_mii;
#else
  ethernet_cfg_if i_cfg[1];
  ethernet_rx_if i_rx[1];
  ethernet_tx_if i_tx[1];
#endif
  smi_if i_smi;

  par {
#if RAW
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE)
#else
    on tile[1]: mii_ethernet_mac(i_cfg, 1, i_rx, 1, i_tx, 1,
                                 p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                                 eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);
#endif
    on tile[1]: [[distribute]] smi_singleport(i_smi, p_smi, 1, 0);

    on tile[1]: {
      p_rst_shared <: 0xF;
#if RAW
      xtcp_uip(i_xtcp, REFLECT_PROCESSES, i_mii,
               null, null, null,
               i_smi, ETHERNET_SMI_PHY_ADDRESS,
               null, otp_ports, ipconfig);
#else
      xtcp_uip(i_xtcp, REFLECT_PROCESSES, null,
                i_cfg[0], i_rx[0], i_tx[0],
                i_smi, ETHERNET_SMI_PHY_ADDRESS,
                null, otp_ports, ipconfig);
#endif
    }

    // The simple udp reflector thread
    par (int i=0; i<REFLECT_PROCESSES; i++) {
      on tile[0]: udp_reflect(i_xtcp[i], INCOMING_PORT+(i*10));
    }

  }
  return 0;
}

#endif
