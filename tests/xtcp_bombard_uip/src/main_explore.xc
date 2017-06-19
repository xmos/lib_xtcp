// Copyright (c) 2017, XMOS Ltd, All rights reserved
#include "common.h"

#if EXPLORER_KIT

// eXplorerKIT RGMII port map
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

port p_smi_mdio   = on tile[1]: XS1_PORT_1C;
port p_smi_mdc    = on tile[1]: XS1_PORT_1D;
port p_eth_reset  = on tile[1]: XS1_PORT_1N;

xtcp_ipconfig_t ipconfig = {
        { 192, 168,   1, 198 }, // ip address (eg 192,168,0,2)
        { 255, 255, 255,   0 }, // netmask    (eg 255,255,255,0)
        {   0,   0,   0,   0 }  // gateway    (eg 192,168,0,1)
};


[[combinable]]
void ar8035_phy_driver(client interface smi_if smi,
                client interface ethernet_cfg_if eth) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  //ethernet_speed_t link_speed = LINK_1000_MBPS_FULL_DUPLEX;
  ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
  const int phy_reset_delay_ms = 1;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x4;
  timer tmr;
  int t;
  tmr :> t;
  p_eth_reset <: 0;
  delay_milliseconds(phy_reset_delay_ms);
  p_eth_reset <: 1;

  while (smi_phy_is_powered_down(smi, phy_address));
  //smi_configure(smi, phy_address, LINK_1000_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);
  smi_configure(smi, phy_address, LINK_100_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);

  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Read AR8035 status register bits 15:14 to get the current link speed
      if (new_state == ETHERNET_LINK_UP) {
        link_speed = (ethernet_speed_t)(smi.read_reg(phy_address, 0x11) >> 14) & 3;
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      break;
    }
  }
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

    on tile[1].core[0]: ar8035_phy_driver(i_smi, i_cfg[CFG_TO_PHY_DRIVER]);

    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: xtcp_uip(i_xtcp, REFLECT_PROCESSES, null,
                      i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                      null, ETHERNET_SMI_PHY_ADDRESS,
                      null, otp_ports, ipconfig);

    // The simple udp reflector thread
    par (int i=0; i<REFLECT_PROCESSES; i++) {
      on tile[0]: udp_reflect(i_xtcp[i], INCOMING_PORT+(i*10));
    }

  }
  return 0;
}

#endif
