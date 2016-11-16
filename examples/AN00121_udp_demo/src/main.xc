// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#include <platform.h>
#include <string.h>
#include <print.h>
#include "xtcp.h"
#include "xtcp_uip_includes.h"

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

port p_smi_mdio = on tile[1]: XS1_PORT_1M;
port p_smi_mdc  = on tile[1]: XS1_PORT_1N;

// These ports are for accessing the OTP memory
otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

// IP Config - change this to suit your network.  Leave with all
// 0 values to use DHCP/AutoIP
xtcp_ipconfig_t ipconfig = {
        { 0, 0, 0, 0 }, // ip address (eg 192,168,0,2)
        { 0, 0, 0, 0 }, // netmask (eg 255,255,255,0)
        { 0, 0, 0, 0 } // gateway (eg 192,168,0,1)
};

// Defines
#define RX_BUFFER_SIZE 300
#define INCOMING_PORT 15533
#define BROADCAST_INTERVAL 600000000
#define BROADCAST_PORT 15534
#define BROADCAST_ADDR {255,255,255,255}
#define BROADCAST_MSG "XMOS Broadcast\n"
#define INIT_VAL -1

static inline void printip(xtcp_ipaddr_t ipaddr)
{
  printint(uip_ipaddr1(ipaddr));
  printstr(".");
  printint(uip_ipaddr2(ipaddr));
  printstr(".");
  printint(uip_ipaddr3(ipaddr));
  printstr(".");
  printint(uip_ipaddr4(ipaddr));
}

/** Simple UDP reflection thread.
 *
 * This thread does two things:
 *
 *   - Reponds to incoming packets on port INCOMING_PORT and
 *     with a packet with the same content back to the sender.
 *   - Periodically sends out a fixed packet to a broadcast IP address.
 *
 */
void udp_reflect(client xtcp_if i_xtcp)
{
  xtcp_connection_t conn;  // A temporary variable to hold
                           // connections associated with an event
  xtcp_connection_t responding_connection; // The connection to the remote end
                                           // we are responding to
  xtcp_connection_t broadcast_connection; // The connection out to the broadcast
                                          // address
  xtcp_ipaddr_t broadcast_addr = BROADCAST_ADDR;

  timer tmr;
  unsigned int time;
  unsigned data_len = 0; // A temporary variable to hold the length of the packet
                         // recieved from get_packet()

  // The buffers for incoming data, outgoing responses and outgoing broadcast
  // messages
  char rx_buffer[RX_BUFFER_SIZE];
  char tx_buffer[RX_BUFFER_SIZE];
  char broadcast_buffer[RX_BUFFER_SIZE] = BROADCAST_MSG;

  int response_len;  // The length of the response the thread is sending
  int broadcast_len; // The length of the broadcast message the thread is
                     // sending


  // Maintain track of two connections. Initially they are not initialized
  // which can be represented by setting their ID to -1
  responding_connection.id = INIT_VAL;
  broadcast_connection.id = INIT_VAL;

  // Instruct server to listen and create new connections on the incoming port
  i_xtcp.listen(INCOMING_PORT, XTCP_PROTOCOL_UDP);

  tmr :> time;
  while (1) {
    select {
      // Respond to an event from the tcp server
      case i_xtcp.packet_ready():
        i_xtcp.get_packet(conn, (char *)rx_buffer, RX_BUFFER_SIZE, data_len);
        switch (conn.event)
          {
          case XTCP_IFUP:
            // Show the IP address of the interface
            xtcp_ipconfig_t ipconfig;
            i_xtcp.get_ipconfig(ipconfig);
            printstr("dhcp: ");
            printip(ipconfig.ipaddr);
            printstr("\n");

            // When the interface goes up, set up the broadcast connection.
            // This connection will persist while the interface is up
            // and is only used for outgoing broadcast messages
            i_xtcp.connect(BROADCAST_PORT,
                           broadcast_addr,
                           XTCP_PROTOCOL_UDP);
            break;

          case XTCP_IFDOWN:
            // Tidy up and close any connections we have open
            if (responding_connection.id != INIT_VAL) {
              i_xtcp.close(responding_connection);
              responding_connection.id = INIT_VAL;
            }
            if (broadcast_connection.id != INIT_VAL) {
              i_xtcp.close(broadcast_connection);
              broadcast_connection.id = INIT_VAL;
            }
            break;

          case XTCP_NEW_CONNECTION:
            // The tcp server is giving us a new connection.
            // It is either a remote host connecting on the listening port
            // or the broadcast connection the threads asked for with
            // the xtcp_connect() call
            if (XTCP_IPADDR_CMP(conn.remote_addr, broadcast_addr)) {
              // This is the broadcast connection
              printstr("New broadcast connection established:");
              printintln(conn.id);
              broadcast_connection = conn;
           }
            else {
              // This is a new connection to the listening port
              printstr("New connection to listening port:");
              printintln(conn.local_port);
              if (responding_connection.id == INIT_VAL) {
                responding_connection = conn;
              }
              else {
                printstr("Cannot handle new connection");
                i_xtcp.close(conn);
              }
            }
            break;

          case XTCP_RECV_DATA:
            // When we get a packet in:
            //
            //  - fill the tx buffer
            //  - send a response to that connection
            //
            printstr("Got data: ");
            printint(data_len);
            printstr(" bytes\n");

            response_len = data_len;
            for (int i=0;i<response_len;i++)
              tx_buffer[i] = rx_buffer[i];

            i_xtcp.send(conn, tx_buffer, response_len);
            printstr("Responding\n");
            break;

        case XTCP_RESEND_DATA:
          // The tcp server wants data, this may be for the broadcast connection
          // or the reponding connection

          if (conn.id == broadcast_connection.id) {
            i_xtcp.send(conn, broadcast_buffer, broadcast_len);
          }
          else {
            i_xtcp.send(conn, tx_buffer, response_len);
          }
          break;

        case XTCP_SENT_DATA:
          if (conn.id == broadcast_connection.id) {
            // When a broadcast message send is complete the connection is kept
            // open for the next one
            printstr("Sent Broadcast\n");
          }
          else {
            // When a reponse is sent, the connection is closed opening up
            // for another new connection on the listening port
            printstr("Sent Response\n");
            i_xtcp.close(conn);
            responding_connection.id = INIT_VAL;
          }
          break;

        case XTCP_TIMED_OUT:
        case XTCP_ABORTED:
        case XTCP_CLOSED:
          printstr("Closed connection:");
          printintln(conn.id);
          break;
        }
      break;

    // This is the periodic case, it occurs every BROADCAST_INTERVAL
    // timer ticks
    case tmr when timerafter(time + BROADCAST_INTERVAL) :> void:
      // A broadcast message can be sent if the connection is established
      // and one is not already being sent on that connection
      if (broadcast_connection.id != INIT_VAL)  {
        printstr("Sending broadcast message\n");
        broadcast_len = strlen(broadcast_buffer);
        i_xtcp.send(conn, broadcast_buffer, broadcast_len);
      }
      time += BROADCAST_INTERVAL;
      break;
    }
  }
}

#define XTCP_MII_BUFSIZE (4096)
#define ETHERNET_SMI_PHY_ADDRESS (0)

int main(void) {
  xtcp_if i_xtcp[1];
  mii_if i_mii;
  smi_if i_smi;
  par {
    // MII/ethernet driver
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE)

    // SMI/ethernet phy driver
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    // TCP component
    on tile[1]: xtcp_uip(i_xtcp, 1, i_mii,
                         null, null, null,
                         i_smi, ETHERNET_SMI_PHY_ADDRESS,
                         null, otp_ports, ipconfig);

    // The simple udp reflector thread
    on tile[0]: udp_reflect(i_xtcp[0]);

  }
  return 0;
}
