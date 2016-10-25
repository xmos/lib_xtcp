// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <platform.h>
#include <string.h>
#include "debug_print.h"
#include <xtcp.h>
#include <stdlib.h>
#include <xassert.h>

#include "otp_board_info.h"
#include "ethernet.h"
#include "smi.h"

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

#elif EXPLORER_KIT

// eXplorerKIT RGMII port map
otp_ports_t otp_ports = on tile[0]: OTP_PORTS_INITIALIZER;

rgmii_ports_t rgmii_ports = on tile[1]: RGMII_PORTS_INITIALIZER;

port p_smi_mdio   = on tile[1]: XS1_PORT_1C;
port p_smi_mdc    = on tile[1]: XS1_PORT_1D;
port p_eth_reset  = on tile[1]: XS1_PORT_1N;

#elif MIC_ARRAY

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

#else

#error "Unknown board"

#endif

#if 1
// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
        { 0, 0, 0, 0 }, // ip address (eg 192,168,0,2)
        { 0, 0, 0, 0 }, // netmask (eg 255,255,255,0)
        { 0, 0, 0, 0 } // gateway (eg 192,168,0,1)
};
#else
xtcp_ipconfig_t ipconfig = {
        { 10 , 0, 102, 198 }, // ip address (eg 192,168,0,2)
        { 255, 255, 240,   0 }, // netmask    (eg 255,255,255,0)
        {  10,   0, 102,   3 }  // gateway    (eg 192,168,0,1)
};
#endif

// Defines
#define RX_BUFFER_SIZE 1460
#define INCOMING_PORT 15533
#define HOST_PORT 15999
#define INIT_VAL -1

#ifndef OPEN_PORTS_PER_PROCESS
#define OPEN_PORTS_PER_PROCESS 1
#endif

#ifndef REFLECT_PROCESSES
#define REFLECT_PROCESSES 1
#endif

#ifndef PROTOCOL
#define PROTOCOL XTCP_PROTOCOL_UDP
#endif

#if EXPLORER_KIT
// An enum to manage the array of connections from the ethernet component
// to its clients.
enum eth_clients {
  ETH_TO_XTCP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_XTCP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
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

#endif  //EXPLORER_KIT

/** Simple TCP/UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the contents reversed back to the sender.
 *
 */
void udp_reflect(client xtcp_if i_xtcp, int start_port)
{
  // A temporary variable to hold connections associated with an event
  xtcp_connection_t conn;
  unsigned return_len = 0;

  // The buffers for incoming data and outgoing responses
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];

  // Instruct server to listen and create new connections on the incoming port
  for(int i=start_port; i<start_port+OPEN_PORTS_PER_PROCESS; i++) {
    debug_printf("Listening on port: %d\n", i);
    i_xtcp.listen(i, PROTOCOL);
  }

  while (1) {
    select {
      case i_xtcp.packet_ready():
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, return_len);
        switch(conn.event) {
          case XTCP_IFUP:
            debug_printf("UP!\n");
            break;
          case XTCP_IFDOWN:
            // debug_printf("DOWN!\n");
            break;
          case XTCP_RECV_DATA:
            for(int copy=0; copy<return_len; copy++)
              tx_buffer[copy] = rx_buffer[return_len - copy - 1];
            i_xtcp.send(conn, tx_buffer, return_len);
            break;
          case XTCP_SENT_DATA:
            // debug_printf("SENT!\n");
            break;
          case XTCP_NEW_CONNECTION:
            // debug_printf("NEW CONN CLIENT!\n");
            break;

          case XTCP_ABORTED:
            // debug_printf("ABORTED!");
            break;

          case XTCP_CLOSED:
            // debug_printf("CLOSED!\n");
            break;
        }
        break;
    }
  }
}

void connect(client xtcp_if i_xtcp, int remote_port)
{
  xtcp_connection_t conn;
  unsigned return_len = 0;

  char rx_buffer[RX_BUFFER_SIZE] = {0};
  char tx_buffer[RX_BUFFER_SIZE] = {'b', 'c', 'd', 'e', 'f'};

  unsigned char ipaddr[4] = {192, 168, 2, 1};

  while (1) {
    select {
      case i_xtcp.packet_ready():
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, return_len);
        switch(conn.event) {
          case XTCP_IFUP:
            i_xtcp.connect(remote_port, ipaddr, PROTOCOL);
            break;
          case XTCP_RECV_DATA:
            if(rx_buffer[0] == 'a') {
              i_xtcp.abort(conn);
            }
            for(int i=0; i<return_len; i++) {
              if(tx_buffer[i] != rx_buffer[i]) {
                debug_printf("Error: Mismatch");
              }
            }
            i_xtcp.send(conn, tx_buffer, 5);
            break;
          case XTCP_NEW_CONNECTION:
            i_xtcp.send(conn, tx_buffer, 5);
            break;

          case XTCP_ABORTED:
            exit(0);
            break;

          case XTCP_CLOSED:
            if(PROTOCOL == XTCP_PROTOCOL_UDP)
              exit(0);
            break;
        }
        break;
    }
  }
}

void udp_bind_local_and_remote(client xtcp_if i_xtcp, int local_port, int remote_port)
{
  xtcp_connection_t conn;
  unsigned return_len = 0;

  char rx_buffer[RX_BUFFER_SIZE] = {0};
  char tx_buffer[RX_BUFFER_SIZE] = {'b', 'c', 'd', 'e', 'f'};

  unsigned char ipaddr[4] = {192, 168, 2, 1};

  while (1) {
    select {
      case i_xtcp.packet_ready():
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, return_len);
        switch(conn.event) {
          case XTCP_IFUP:
            /* Listen on wrong local port */
            i_xtcp.connect(local_port+10, ipaddr, XTCP_PROTOCOL_UDP);
            break;
          case XTCP_RECV_DATA:
            if(rx_buffer[0] == 'a') {
              i_xtcp.abort(conn);
            } else {
              for(int i=0; i<return_len; i++) {
                if(tx_buffer[i] != rx_buffer[i]) {
                  debug_printf("Error: Mismatch");
                }
              }
            }
            i_xtcp.send(conn, tx_buffer, 5);
            break;
          case XTCP_NEW_CONNECTION:
            /* Change local binding */
            i_xtcp.bind_local_udp(conn, local_port);
            i_xtcp.bind_remote_udp(conn, ipaddr, remote_port);
            i_xtcp.send(conn, tx_buffer, 5);
            break;

          case XTCP_CLOSED:
            exit(0);
            break;
        }
        break;
    }
  }
}

void multicast(client xtcp_if i_xtcp)
{
  xtcp_connection_t conn;
  unsigned return_len = 0;

  char rx_buffer[RX_BUFFER_SIZE] = {0};
  char tx_buffer[RX_BUFFER_SIZE] = {'b', 'c', 'd', 'e', 'f'};

  unsigned char ipaddr[4] = {244, 1, 1, 1};
  // i_xtcp.join_multicast_group(ipaddr);
  // i_xtcp.listen(5007, XTCP_PROTOCOL_UDP);

  while (1) {
    select {
      case i_xtcp.packet_ready():
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, return_len);
        switch(conn.event) {
          case XTCP_IFUP:
            debug_printf("UP!\n");
            break;
          case XTCP_RECV_DATA:
            debug_printf("DATA!\n");
            if(rx_buffer[0] == 'a') {
              i_xtcp.abort(conn);
            } else {
              for(int i=0; i<return_len; i++) {
                if(tx_buffer[i] != rx_buffer[i]) {
                  debug_printf("Error: Mismatch");
                }
              }
            }
            // i_xtcp.send(conn, tx_buffer, 5);
            break;
          case XTCP_NEW_CONNECTION:
            /* Change local binding */
            debug_printf("NEW CONN\n");
            // i_xtcp.send(conn, tx_buffer, 5);
            break;

          case XTCP_CLOSED:
            exit(0);
            break;
        }
        break;
    }
  }
}

#define XTCP_MII_BUFSIZE (4096)
#define ETHERNET_SMI_PHY_ADDRESS (0)

#if SLICEKIT_L16 || MIC_ARRAY
int main(void) {
  xtcp_if i_xtcp[REFLECT_PROCESSES];
  smi_if i_smi;

#if RAW
  mii_if i_mii;
  par {
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE)

#else // ETH
  ethernet_cfg_if i_cfg[1];
  ethernet_rx_if i_rx[1];
  ethernet_tx_if i_tx[1];
  par {
    on tile[1]: mii_ethernet_mac(i_cfg, 1, i_rx, 1, i_tx, 1,
                                 p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                                 p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                                 eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);
#endif

#if SLICEKIT_L16
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);
#else // MIC_ARRAY
    on tile[1]: [[distribute]] smi_singleport(i_smi, p_smi, 1, 0);
#endif

    on tile[1]: {
#if MIC_ARRAY
      p_rst_shared <: 0xF;
#endif

#if RAW
      xtcp_lwip(i_xtcp, REFLECT_PROCESSES, i_mii,
           null, null, null,
           i_smi, ETHERNET_SMI_PHY_ADDRESS,
           null, otp_ports, ipconfig);
#else // ETH
      xtcp_lwip(i_xtcp, REFLECT_PROCESSES, null,
           i_cfg[0], i_rx[0], i_tx[0],
           i_smi, ETHERNET_SMI_PHY_ADDRESS,
           null, otp_ports, ipconfig);
#endif
    }

#if CONNECT
    on tile[0]: connect(i_xtcp[0], INCOMING_PORT);
#elif BIND
    on tile[0]: udp_bind_local_and_remote(i_xtcp[0], INCOMING_PORT, HOST_PORT);
#elif MULTICAST
    on tile[0]: multicast(i_xtcp[0]);
#else
    par (int i=0; i<REFLECT_PROCESSES; i++) {
      on tile[0]: udp_reflect(i_xtcp[i], INCOMING_PORT+(i*10));
    }
#endif
  }
  return 0;
}

#else
/* eXplorerKIT */

int main(void) {
  chan c_xtcp[REFLECT_PROCESSES];
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

    on tile[0]: xtcp_lwip(c_xtcp, REFLECT_PROCESSES, null,
                      i_cfg[CFG_TO_XTCP], i_rx[ETH_TO_XTCP], i_tx[ETH_TO_XTCP],
                      null, ETHERNET_SMI_PHY_ADDRESS,
                      null, otp_ports, ipconfig);

    // The simple udp reflector thread
    par (int i=0; i<REFLECT_PROCESSES; i++) {
      on tile[0]: udp_reflect(c_xtcp[i], INCOMING_PORT+(i*10));
    }

  }
  return 0;
} //EXPLORER_KIT

#endif