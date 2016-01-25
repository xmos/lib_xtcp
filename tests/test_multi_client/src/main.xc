// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <platform.h>
#include "xtcp.h"
#include "smi.h"
#include "otp_board_info.h"
#include "debug_print.h"

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

// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP
xtcp_ipconfig_t ipconfig = {
  { 0, 0, 0, 0 }, // ip address (eg 192,168,0,2)
  { 0, 0, 0, 0 }, // netmask (eg 255,255,255,0)
  { 0, 0, 0, 0 }  // gateway (eg 192,168,0,1)
};

#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15533
#define BROADCAST_INTERVAL 600000000
#define BROADCAST_PORT 15534

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *   - Periodically sends out a fixed packet to a broadcast IP address.
 *
 */
void udp_reflect(chanend c_xtcp, int port0, int port1)
{
  xtcp_connection_t conn;
  xtcp_connection_t responding_connection;
  xtcp_connection_t broadcast_connection;

  xtcp_ipaddr_t broadcast_addr = {255,255,255,255};
  int send_flag = 0;

  int broadcast_send_flag = 0;

  timer tmr;
  unsigned int time;

  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];
  char broadcast_buffer[RX_BUFFER_SIZE];

  int response_len;
  int broadcast_len;

  responding_connection.id = -1;
  broadcast_connection.id = -1;

  xtcp_listen(c_xtcp, port0, XTCP_PROTOCOL_UDP);

  tmr :> time;
  while (1) {
    select {

    case xtcp_event(c_xtcp, conn):
      switch (conn.event)
        {
        case XTCP_IFUP:
          xtcp_connect(c_xtcp,
                       port1,
                       broadcast_addr,
                       XTCP_PROTOCOL_UDP);
          break;
        case XTCP_IFDOWN:
          if (responding_connection.id != -1) {
            xtcp_close(c_xtcp, responding_connection);
            responding_connection.id = -1;
          }
          if (broadcast_connection.id != -1) {
            xtcp_close(c_xtcp, broadcast_connection);
            responding_connection.id = -1;
          }
          break;
        case XTCP_NEW_CONNECTION:
          if (XTCP_IPADDR_CMP(conn.remote_addr, broadcast_addr)) {
            debug_printf("New broadcast connection established: %d\n", conn.id);
            broadcast_connection = conn;
          }
          else {
            debug_printf("New connection to listening port: %d\n", conn.local_port);
            if (responding_connection.id == -1) {
              responding_connection = conn;
            }
            else {
              debug_printf("Cannot handle new connection\n");
              xtcp_close(c_xtcp, conn);
            }
          }
          break;
        case XTCP_RECV_DATA:
          response_len = xtcp_recv_count(c_xtcp, rx_buffer, RX_BUFFER_SIZE);
          debug_printf("Got data: %d bytes\n", response_len);

          for (int i=0;i<response_len;i++)
            tx_buffer[i] = rx_buffer[i];

          if (!send_flag) {
            xtcp_init_send(c_xtcp, conn);
            send_flag = 1;
            debug_printf("Responding\n");
          }
          else {
            // Cannot respond here since the send buffer is being used
          }
          break;
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:

        if (conn.id == broadcast_connection.id) {
          xtcp_send(c_xtcp, broadcast_buffer, broadcast_len);
        }
        else {
          xtcp_send(c_xtcp, tx_buffer, response_len);
        }
        break;
      case XTCP_SENT_DATA:
        xtcp_complete_send(c_xtcp);
        if (conn.id == broadcast_connection.id) {
          debug_printf("Sent Broadcast on conn %d\n", conn.id);
          broadcast_send_flag = 0;
        }
        else {
          debug_printf("Sent Response\n");
          xtcp_close(c_xtcp, conn);
          responding_connection.id = -1;
          send_flag = 0;
        }
        break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
        debug_printf("Closed connection: %d\n", conn.id);
        break;
      case XTCP_ALREADY_HANDLED:
          break;
      }
      break;

    case tmr when timerafter(time + BROADCAST_INTERVAL) :> void:

      if (broadcast_connection.id != -1 && !broadcast_send_flag)  {
        broadcast_len = 100;
        xtcp_init_send(c_xtcp, broadcast_connection);
        broadcast_send_flag = 1;
      }
      tmr :> time;
      break;
    }
  }
}

#define XTCP_MII_BUFSIZE 4096
#define NUM_CLIENTS 4

int main(void) {
  chan c_xtcp[NUM_CLIENTS];
  mii_if i_mii;
  smi_if i_smi;

  par {
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);

    on tile[1]: xtcp(c_xtcp, 1, i_mii,
                     null, null, null,
                     i_smi, 0,
                     null, otp_ports, ipconfig);

    // SMI/ethernet phy driver
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    par (int i=0; i < NUM_CLIENTS; i++)
      on tile[0]: udp_reflect(c_xtcp[i], INCOMING_PORT+i, BROADCAST_PORT+i);
  }

  return 0;
}
