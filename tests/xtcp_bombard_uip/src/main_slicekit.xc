// Copyright (c) 2017, XMOS Ltd, All rights reserved
#include "common.h"

#if SLICEKIT_L16
// Here are the port definitions required by ethernet. This port assignment
// is for the L16 sliceKIT with the ethernet slice plugged into the
// CIRCLE slot.
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

// SMI
port p_smi_mdio = on tile[1]: XS1_PORT_1M;
port p_smi_mdc  = on tile[1]: XS1_PORT_1N;

// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

xtcp_ipconfig_t ipconfig = {
        { 192, 168,   1, 196 }, // ip address (eg 192,168,0,2)
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
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
#if RAW
    on tile[1]: xtcp_uip(i_xtcp, REFLECT_PROCESSES, i_mii,
                         null, null, null,
                         i_smi, ETHERNET_SMI_PHY_ADDRESS,
                         null, otp_ports, ipconfig);
#else
    on tile[1]: xtcp_uip(i_xtcp, REFLECT_PROCESSES, null,
                          i_cfg[0], i_rx[0], i_tx[0],
                          i_smi, ETHERNET_SMI_PHY_ADDRESS,
                          null, otp_ports, ipconfig);
#endif

    // The simple udp reflector thread
    on tile[0]: {
      par (int i=0; i<REFLECT_PROCESSES; i++) {
        udp_reflect(i_xtcp[i], INCOMING_PORT+(i*10));
      }
      exit(0);
    }
  }
  return 0;
}

#endif
