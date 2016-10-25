// Copyright (c) 2012-2016, XMOS Ltd, All rights reserved

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

#define RX_BUFFER_SIZE 1200
#define TX_BUFFER_SIZE 1200

#define INCOMING_PORT_UDP 100
#define INCOMING_PORT_TCP 101


/*
 *  This thread implements three 'server' like services.
 *
 *  On UDP 100 there is a listening port that does not close any connections
 *  that are opened by remote machines.  One of the test scripts opens a single
 *  socket to this port, and streams data to it.  This mimics a continuously
 *  open type UDP connection, for instance a UDP media stream, where the close
 *  action is as the result of a higher layer connection management action.
 *
 *  On UDP 101 there is a listening port that closes the connection every time
 *  a piece of data is received.  One test script repeatedly opens a socket,
 *  sends a single piece of data, and then closes the socket.  This mimics a
 *  discovery type protocol, where units are sending single packet 'here i am'
 *  messages to each other.
 *
 *  On TCP 100, there is a listening socket which does not close the connection.
 *  The test script opens the connection, streams data into the port, then closes
 *  it.  This mimics a long term data sink, such as a data logger, or TCP based
 *  media renderer.
 */
void udp_server(chanend c_xtcp)
{
  xtcp_connection_t conn;

  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[TX_BUFFER_SIZE];

  int response_len;
  static unsigned send_count = 0;

  for (unsigned i=0; i<(sizeof(tx_buffer)+3)/4; ++i) (tx_buffer,unsigned[])[i] = i;

  xtcp_listen(c_xtcp, INCOMING_PORT_UDP, XTCP_PROTOCOL_UDP);
  xtcp_listen(c_xtcp, INCOMING_PORT_TCP, XTCP_PROTOCOL_TCP);

  while (1) {
    select {

    // Respond to an event from the tcp server
    case xtcp_event(c_xtcp, conn):
      switch (conn.event)
        {
        case XTCP_IFUP:
        case XTCP_IFDOWN:
          break;

        case XTCP_NEW_CONNECTION:
          break;
        case XTCP_RECV_DATA:
          response_len = xtcp_recv_count(c_xtcp, rx_buffer, RX_BUFFER_SIZE);
          switch (conn.local_port) {
          case INCOMING_PORT_UDP:
              send_count = 0;
              xtcp_init_send(c_xtcp, conn);
              break;
          case INCOMING_PORT_TCP:
              send_count = 0;
              xtcp_init_send(c_xtcp, conn);
              break;
          }
          break;
      case XTCP_REQUEST_DATA:
      case XTCP_RESEND_DATA:
      case XTCP_SENT_DATA:
          if (conn.event != XTCP_RESEND_DATA) {
              send_count++;
          }
          if (send_count > 100000) {
              // Done sending
              xtcp_complete_send(c_xtcp);
          } else {
              (tx_buffer,unsigned[])[0] = send_count;
              xtcp_send(c_xtcp, tx_buffer, sizeof(tx_buffer));
          }
          break;
      case XTCP_TIMED_OUT:
      case XTCP_ABORTED:
      case XTCP_CLOSED:
      case XTCP_ALREADY_HANDLED:
          break;
      }
      break;
    }
  }
}

#define XTCP_MII_BUFSIZE 4096

int main(void) {
    chan c_xtcp[1];
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

    on tile[0]: udp_server(c_xtcp[0]);

    }
    return 0;
}
