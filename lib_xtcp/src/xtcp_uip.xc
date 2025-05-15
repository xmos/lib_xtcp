// Copyright (c) 2016-2017, XMOS Ltd, All rights reserved
#include "xtcp.h"
#include <string.h>
#include <xassert.h>
#include <print.h>
#include <malloc.h>
// Used to prevent conflict with uIP
#include "xtcp_uip_includes.h"
#include "xtcp_shared.h"
#include "xtcp_uip/xcoredev.h"

#include "debug_print.h"

#define ETHBUF (&uip_struct->eth_hdr)
#define UDPBUF (&uip_struct->udpip_hdr)

#define NO_CLIENT -1

#define set_uip_state(conn) \
  do { \
    if(conn.protocol == XTCP_PROTOCOL_UDP) { \
      uip_udp_conn = (struct uip_udp_conn * unsafe) conn.stack_conn; \
      uip_conn = NULL; \
    } else { \
      uip_conn = (struct uip_conn * unsafe) conn.stack_conn; \
      uip_udp_conn = NULL; \
    } \
  } while (0)

typedef struct listener_info_t {
  unsigned active;
  unsigned port_number;
  int client_num; // Can be NO_CLIENT
} listener_info_t;

listener_info_t tcp_listeners[NUM_TCP_LISTENERS] = {{0}};
listener_info_t udp_listeners[NUM_UDP_LISTENERS] = {{0}};

// uIP global variables
extern unsigned short uip_len;     // Length of data in buffer
extern unsigned short uip_slen;    // Length of data to be sent in buffer
extern void * unsafe uip_sappdata; // Pointer to start position of data in packet buffer
unsigned int uip_buf32[(UIP_BUFSIZE + 5) >> 2];  // uIP buffer in 32bit words, for alignment
unsafe {
  u8_t * unsafe uip_buf = (u8_t *) &uip_buf32[0];/* uIP buffer 8bit */
}

struct uip_buf_s {
  struct uip_eth_hdr   eth_hdr;
  struct uip_udpip_hdr udpip_hdr;
};
unsafe {
  struct uip_buf_s * unsafe uip_struct = (struct uip_buf_s *) &uip_buf32[0];
}

// Extra buffer to hold data until the client is ready
unsigned int rx_buffer[(UIP_BUFSIZE + 5) >> 2];

// These pointers are used to store connections for sending in xcoredev.xc
extern client interface ethernet_tx_if unsafe xtcp_i_eth_tx_uip;
extern client interface mii_if unsafe xtcp_i_mii_uip;
extern mii_info_t xtcp_mii_info_uip;
extern enum xcoredev_eth_e xcoredev_eth;

static unsigned uip_static_ip = 0; // Boolean whether we're using a static IP
xtcp_ipconfig_t uip_static_ipconfig;
static unsigned buffer_full = 0;   // Boolean whether the RX buffer is full

static int dhcp_done = 0;

#if UIP_USE_DHCP
unsafe void
dhcpc_configured(const struct dhcpc_state * unsafe s)
{
#if UIP_USE_AUTOIP
  uip_autoip_stop();
#endif
  uip_sethostaddr(s->ipaddr);
  uip_setdraddr(s->default_router);
  uip_setnetmask(s->netmask);
  xtcp_if_up();
  dhcp_done = 1;
}
#endif

#if UIP_USE_AUTOIP
void
uip_autoip_configured(uip_ipaddr_t autoip_ipaddr)
{
  if (!dhcp_done) {
    uip_ipaddr_t ipaddr;
    uip_sethostaddr(autoip_ipaddr);
    uip_ipaddr(ipaddr, 255, 255, 0, 0);
    uip_setnetmask(ipaddr);
    uip_ipaddr(ipaddr, 0, 0, 0, 0);
    uip_setdraddr(ipaddr);
    xtcp_if_up();
  }
}
#endif

static int
get_listener_linknum(listener_info_t listeners[],
                     int n_ports,
                     int local_port)
{
  int client_num = NO_CLIENT;
  for (int i=0; i<n_ports; i++) {
    if (listeners[i].active &&
        local_port == listeners[i].port_number) {
      client_num = listeners[i].client_num;
      break;
    }
  }
  return client_num;
}

static void
unregister_listener(listener_info_t listeners[],
                    int client_num,
                    int port_number,
                    int n_ports)
{
  for (int i=0; i<n_ports; i++) {
    if (listeners[i].active &&
      listeners[i].port_number == port_number) {
      listeners[i].active = 0;
    }
  }
}

static void
register_listener(listener_info_t listeners[],
                  int client_num,
                  int port_number,
                  int n_ports)
{
  int i;
  for (i=0; i<n_ports; i++) {
    if (!listeners[i].active) {
      break;
    }
  }

  if (i==n_ports) {
    fail("Max number of listeners reached");
  } else {
    listeners[i].active = 1;
    listeners[i].port_number = port_number;
    listeners[i].client_num = client_num;
  }
}

void
uip_linkup(void)
{
  if (uip_static_ip) {
    uip_sethostaddr(uip_static_ipconfig.ipaddr);
    uip_setdraddr(uip_static_ipconfig.gateway);
    uip_setnetmask(uip_static_ipconfig.netmask);
    xtcp_if_up();
  } else {
    dhcp_done = 0;
#if UIP_USE_DHCP
    dhcpc_stop();
#endif
#if UIP_USE_AUTOIP
#if UIP_USE_DHCP
    uip_autoip_stop();
#else
    uip_autoip_start();
#endif
#endif
#if UIP_USE_DHCP
    dhcpc_start();
#endif
  }
}

void uip_linkdown(void )
{
  dhcp_done = 0;
#if UIP_USE_DHCP
  dhcpc_stop();
#endif
#if UIP_USE_AUTOIP
  uip_autoip_stop();
#endif
}

static unsigned is_ipaddr_static(xtcp_ipaddr_t ipaddr) {
  unsigned is_static = 0;
  if ((ipaddr[0] != 0) || (ipaddr[1] != 0) || (ipaddr[2] != 0) || (ipaddr[3] != 0)) {
    is_static = 1;
  }
  return is_static;
}

static unsafe void
xtcp_uip_init(xtcp_ipconfig_t* ipconfig, unsigned char mac_address[6]) {
  if (ipconfig != NULL) {
    memcpy(&uip_static_ipconfig, ipconfig, sizeof(xtcp_ipconfig_t));
  }
  memcpy(&uip_ethaddr, mac_address, 6);
  uip_init();

#if UIP_IGMP
  igmp_init();
#endif

  if (ipconfig != NULL) {
    uip_static_ip = is_ipaddr_static(ipconfig->ipaddr);
  }

  if (ipconfig == NULL) {
    uip_ipaddr_t ipaddr;
    uip_ipaddr(ipaddr, 0, 0, 0, 0);
    uip_sethostaddr(ipaddr);
    uip_setdraddr(ipaddr);
    uip_setnetmask(ipaddr);
  } else {
    uip_sethostaddr(ipconfig->ipaddr);
    uip_setdraddr(ipconfig->gateway);
    uip_setnetmask(ipconfig->netmask);
  }

#if UIP_USE_AUTOIP
    int hwsum = mac_address[0] + mac_address[1] + mac_address[2] +
                mac_address[3] + mac_address[4] + mac_address[5];
    uip_autoip_init(hwsum + (hwsum << 16) + (hwsum << 24));
#endif
#if UIP_USE_DHCP
    dhcpc_init(uip_ethaddr.addr, 6);
#endif
}

static void
xtcp_tx_buffer(void) {
  uip_split_output();
  uip_len = 0;
}

static unsafe void
xtcp_process_incoming_packet(int length)
{
  uip_len = length;
  if (ETHBUF->type == htons(UIP_ETHTYPE_IP)) {
    uip_arp_ipin();
    uip_input(); // Will eventually call xtcpd_appcall
    if (uip_len > 0) {
      if (uip_udpconnection()) {
        uip_arp_out(uip_udp_conn);
      } else {
        uip_arp_out(NULL);
      }
      xtcp_tx_buffer();
    }
    // ARP. No input for application
  } else if (ETHBUF->type == htons(UIP_ETHTYPE_ARP)) {
    uip_arp_arpin();

    if (uip_len > 0) {
      xtcp_tx_buffer();
    }

    for (int i = 0; i < UIP_UDP_CONNS; i++) {
      uip_udp_arp_event(i);
      if (uip_len > 0) {
        uip_arp_out(&uip_udp_conns[i]);
        xtcp_tx_buffer();
      }
    }
  }
}

static unsafe void
xtcp_process_periodic_timer(void)
{
#if UIP_IGMP
  igmp_periodic();
  if(uip_len > 0) {
    xtcp_tx_buffer();
  }
#endif

  for (int i=0; i<UIP_UDP_CONNS; i++) {
    uip_udp_periodic(i);
    if (uip_len > 0) {
      uip_arp_out(&uip_udp_conns[i]);
      xtcp_tx_buffer();
    }
  }

  for (int i=0; i<UIP_CONNS; i++) {
    uip_periodic(i);
    if (uip_len > 0) {
      uip_arp_out(NULL);
      xtcp_tx_buffer();
    }
  }
}

void xtcp_uip(server xtcp_if i_xtcp[n_xtcp],
              static const unsigned n_xtcp,
              client mii_if ?i_mii,
              client ethernet_cfg_if ?i_eth_cfg,
              client ethernet_rx_if ?i_eth_rx,
              client ethernet_tx_if ?i_eth_tx,
              const char (&?mac_address0)[6],
              otp_ports_t &?otp_ports,
              xtcp_ipconfig_t &ipconfig)
{
  // Entire function declared unsafe
  unsafe {

  mii_info_t mii_info;
  timer tmr;
  unsigned timeout;
  unsigned arp_timer=0;
  unsigned autoip_timer=0;
  char mac_address[6];

  if (!isnull(mac_address0)) {
    memcpy(mac_address, mac_address0, 6);
  } else if (!isnull(otp_ports)) {
    otp_board_info_get_mac(otp_ports, 0, mac_address);
  } else if (!isnull(i_eth_cfg)) {
    i_eth_cfg.get_macaddr(0, mac_address);
  } else {
    fail("Must supply OTP ports or MAC address to xtcp component");
  }

  // debug_printf("UIP struct-e: %p\n", &uip_struct->eth_hdr);
  // debug_printf("UIP struct-u: %p\n", &uip_struct->udpip_hdr);

  if (!isnull(i_mii)) {
    mii_info = i_mii.init();
    xtcp_mii_info_uip = mii_info;
    xtcp_i_mii_uip = i_mii;
    xcoredev_eth = XCORE_ETH_MII;
  }

  if (!isnull(i_eth_cfg)) {
    xtcp_i_eth_tx_uip = i_eth_tx;
    xcoredev_eth = XCORE_ETH_TX;
    i_eth_cfg.set_macaddr(0, mac_address);

    size_t index = i_eth_rx.get_index();
    ethernet_macaddr_filter_t macaddr_filter;
    memcpy(macaddr_filter.addr, mac_address, sizeof(mac_address));
    i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

    // Add broadcast filter
    for (size_t i = 0; i < 6; i++)
      macaddr_filter.addr[i] = 0xff;
    i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

    // Only allow ARP and IP packets to the stack
    i_eth_cfg.add_ethertype_filter(index, 0x0806);
    i_eth_cfg.add_ethertype_filter(index, 0x0800);
  }

  xtcp_init_queue(n_xtcp, i_xtcp);
  xtcp_uip_init(&ipconfig, mac_address);

  tmr :> timeout;
  timeout += 10000000;

  while (1) {
    select {
    // Only accept new packets if there's nothing in the buffer already
    case (!isnull(i_mii) && !buffer_full) => mii_incoming_packet(mii_info):
      int * unsafe data;
      int nbytes;
      unsigned timestamp;
      {data, nbytes, timestamp} = i_mii.get_incoming_packet();
      if (data) {
        if (nbytes <= UIP_BUFSIZE) {
          memcpy(uip_buf, data, nbytes);
          xtcp_process_incoming_packet(nbytes);
        }
        i_mii.release_packet(data);
      }
      break;

    // Only accept new packets if there's nothing in the buffer already
    case (!isnull(i_eth_rx) && !buffer_full) => i_eth_rx.packet_ready():
      ethernet_packet_info_t desc;
      i_eth_rx.get_packet(desc, (char *) uip_buf, UIP_BUFSIZE);
      if (desc.type == ETH_DATA) {
        xtcp_process_incoming_packet(desc.len);
      } else if (desc.type == ETH_IF_STATUS) {
        if (uip_buf[0] == ETHERNET_LINK_UP) {
          uip_linkup();
        }
        else {
          uip_linkdown();
        }
      }
      break;

    case i_xtcp[unsigned i].listen(int port_number, xtcp_protocol_t protocol):
      if (protocol == XTCP_PROTOCOL_TCP) {
        uip_listen(HTONS(port_number));
        register_listener(tcp_listeners, i, port_number, NUM_TCP_LISTENERS);
      } else {
        uip_udp_listen(HTONS(port_number));
        register_listener(udp_listeners, i, port_number, NUM_UDP_LISTENERS);
      }
      break;

    case i_xtcp[unsigned i].unlisten(unsigned port_number):
        uip_unlisten(HTONS(port_number));
        unregister_listener(tcp_listeners, i, port_number, NUM_TCP_LISTENERS);

        uip_udp_unlisten(HTONS(port_number));
        unregister_listener(udp_listeners, i, port_number, NUM_UDP_LISTENERS);
      break;

    // Client calls get_packet after the server has notified
    case i_xtcp[unsigned i].get_packet(xtcp_connection_t &conn, char data[n], unsigned int n, unsigned &length):
      unsigned bytecount = 0;
      client_queue_t head = dequeue_event(i);
      head.xtcp_conn->event = head.xtcp_event;
      memcpy(&conn, head.xtcp_conn, sizeof(xtcp_connection_t));

      if(head.xtcp_event == XTCP_RECV_DATA) {
        memcpy(data, rx_buffer, head.xtcp_conn->packet_length);
        buffer_full = 0;
        bytecount = head.xtcp_conn->packet_length;
      }

      length = bytecount;

      renotify(i);
      break;

    case i_xtcp[unsigned i].close(const xtcp_connection_t &conn):
      set_uip_state(conn);

      if (uip_udpconnection()) {
        uip_udp_conn->lport = 0;
        enqueue_event_and_notify(conn.client_num, XTCP_CLOSED, &(uip_udp_conn->xtcp_conn), NULL);
      } else {
        uip_close();
        uip_process(UIP_TCP_SEND);
      }
      break;

    case i_xtcp[unsigned i].abort(const xtcp_connection_t &conn):
      set_uip_state(conn);
      xtcp_connection_t *unsafe xtcp_conn_ptr;

      buffer_full = 0;

      if (uip_udpconnection()) {
        uip_udp_conn->lport = 0;
        xtcp_conn_ptr = &(uip_udp_conn->xtcp_conn);
        enqueue_event_and_notify(conn.client_num, XTCP_CLOSED, xtcp_conn_ptr, NULL);
      } else {
        uip_abort();
        uip_process(UIP_TCP_SEND);
        xtcp_conn_ptr = &(uip_conn->xtcp_conn);
        enqueue_event_and_notify(conn.client_num, XTCP_ABORTED, xtcp_conn_ptr, NULL);
      }

      rm_recv_events(xtcp_conn_ptr->id, i);
      break;

    case i_xtcp[unsigned i].bind_local_udp(const xtcp_connection_t &conn, unsigned port_number):
      set_uip_state(conn);

      if (!uip_udpconnection()) break;

      uip_udp_conn->lport = HTONS(port_number);
      uip_udp_conn->xtcp_conn.local_port = port_number;
      break;

    case i_xtcp[unsigned i].bind_remote_udp(const xtcp_connection_t &conn, xtcp_ipaddr_t ipaddr, unsigned port_number):
      set_uip_state(conn);

      if(!uip_udpconnection()) break;

      // Change ports for xtcp_conn and uip_idp_conn
      uip_udp_conn->xtcp_conn.remote_port = port_number;
      uip_udp_conn->rport = HTONS(port_number);

      // The same for the IP address
      XTCP_IPADDR_CPY(uip_udp_conn->xtcp_conn.remote_addr, ipaddr);
      uip_udp_conn->ripaddr[0] = (ipaddr[1] << 8) | ipaddr[0];
      uip_udp_conn->ripaddr[1] = (ipaddr[3] << 8) | ipaddr[2];
      break;

    case i_xtcp[unsigned i].connect(unsigned port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol):
      uip_ipaddr_t uipaddr;
      uip_ipaddr(uipaddr, ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);

      if (protocol == XTCP_PROTOCOL_TCP) {
        struct uip_conn * unsafe conn = uip_connect(&uipaddr, HTONS(port_number));
        if (conn != NULL) {
          register_listener(tcp_listeners, i, HTONS(conn->lport), NUM_TCP_LISTENERS);
          conn->xtcp_conn = create_xtcp_state(i,
                                        XTCP_PROTOCOL_TCP,
                                        (unsigned char * unsafe) uipaddr,
                                        conn->lport,
                                        port_number,
                                        conn);
        }
      } else {
        struct uip_udp_conn * unsafe conn = uip_udp_new(&uipaddr, HTONS(port_number));
        if (conn != NULL) {
          register_listener(udp_listeners, i, HTONS(conn->lport), NUM_UDP_LISTENERS);
          conn->xtcp_conn = create_xtcp_state(i,
                                              XTCP_PROTOCOL_UDP,
                                              (unsigned char * unsafe) uipaddr,
                                              conn->lport,
                                              port_number,
                                              conn);
          enqueue_event_and_notify(i, XTCP_NEW_CONNECTION, &(conn->xtcp_conn), NULL);
        }
      }
      break;

    case i_xtcp[unsigned i].send(const xtcp_connection_t &conn, char data[], unsigned len):
      if (len <= 0) break;

      set_uip_state(conn);

      // Make sure we're writing to the correct place
      if (uip_udpconnection()) {
        uip_sappdata = uip_appdata = &uip_buf[UIP_LLH_LEN + UIP_IPUDPH_LEN];
      } else {
        uip_sappdata = uip_appdata = &uip_buf[UIP_LLH_LEN + UIP_IPTCPH_LEN];
      }

      memcpy(uip_sappdata, data, len);
      uip_send(uip_sappdata, len);

      if (!uip_udpconnection()) {
        uip_process(UIP_TCP_SEND);
        uip_arp_out(NULL);
      } else {
        uip_process(UIP_UDP_SEND_CONN);
        uip_arp_out(uip_udp_conn);
        enqueue_event_and_notify(conn.client_num, XTCP_SENT_DATA, &(uip_udp_conn->xtcp_conn), NULL);
      }
      xtcp_tx_buffer();
      break;

    case i_xtcp[unsigned i].join_multicast_group(xtcp_ipaddr_t addr):
  #if UIP_IGMP
      uip_ipaddr_t ipaddr;
      uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
      igmp_join_group(ipaddr);
  #endif
      break;

    case i_xtcp[unsigned i].leave_multicast_group(xtcp_ipaddr_t addr):
  #if UIP_IGMP
      uip_ipaddr_t ipaddr;
      uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
      igmp_leave_group(ipaddr);
  #endif
      break;

    case i_xtcp[unsigned i].set_appstate(const xtcp_connection_t &conn, xtcp_appstate_t appstate):
      // Take a local copy to pass to the functions
      const xtcp_connection_t local_conn = conn;

      set_uip_state(local_conn);

      // The stack_conn is a pointer to the a structure belonging to uIP and will
      // therefore reside on this tile.
      if (uip_udpconnection()) {
        uip_udp_conn->xtcp_conn.appstate = appstate;
      } else {
        uip_conn->xtcp_conn.appstate = appstate;
      }
      break;

    case i_xtcp[unsigned i].request_host_by_name(const char hostname[], unsigned name_len):
      // NOT SUPPORTED BY uIP
      break;

    case i_xtcp[unsigned i].get_ipconfig(xtcp_ipconfig_t &ipconfig):
      memcpy(&ipconfig.ipaddr, uip_hostaddr, sizeof(xtcp_ipaddr_t));
      memcpy(&ipconfig.netmask, uip_netmask, sizeof(xtcp_ipaddr_t));
      memcpy(&ipconfig.gateway, uip_draddr, sizeof(xtcp_ipaddr_t));
      break;

    case tmr when timerafter(timeout) :> timeout:
      timeout += 10000000;

      if (++arp_timer == 100) {
        arp_timer=0;
        uip_arp_timer();
      }

#if UIP_USE_AUTOIP
      if (++autoip_timer == 5) {
        autoip_timer = 0;
        uip_autoip_periodic();
        if (uip_len > 0) {
          xtcp_tx_buffer();
        }
      }
#endif

      xtcp_process_periodic_timer();
      break;
    }
  }
  } // unsafe
}

unsafe void
xtcpd_appcall(void)
{
  xtcp_connection_t *unsafe xtcp_conn;

  // DHCP
  if (uip_udpconnection() &&
      (uip_udp_conn->lport == HTONS(DHCPC_CLIENT_PORT) ||
       uip_udp_conn->lport == HTONS(DHCPC_SERVER_PORT))) {
#if UIP_USE_DHCP
    dhcpc_appcall();
#endif
    return;
  }

  // Get connection state
  if (uip_udpconnection()) {
    xtcp_conn = &(uip_udp_conn->xtcp_conn);
    if (uip_newdata()) {
      xtcp_conn->remote_port = HTONS(UDPBUF->srcport);
      uip_ipaddr_copy(xtcp_conn->remote_addr, UDPBUF->srcipaddr);
    }
  } else {
    xassert(uip_conn);
    xtcp_conn = &(uip_conn->xtcp_conn);
    xtcp_conn->mss = uip_mss();
  }

  // New connection
  if (uip_connected()) {
    int client_num;

    if (uip_udpconnection()) {
      client_num = get_listener_linknum(udp_listeners,
                                        NUM_UDP_LISTENERS,
                                        HTONS(uip_udp_conn->lport));

      *xtcp_conn = create_xtcp_state(client_num,
                                     XTCP_PROTOCOL_UDP,
                                     (unsigned char * unsafe) UDPBUF->srcipaddr,
                                     HTONS(uip_udp_conn->lport),
                                     HTONS(UDPBUF->srcport),
                                     uip_udp_conn);
    } else {
      client_num = get_listener_linknum(tcp_listeners,
                                        NUM_TCP_LISTENERS,
                                        HTONS(uip_conn->lport));

      *xtcp_conn = create_xtcp_state(client_num,
                                     XTCP_PROTOCOL_TCP,
                                     (unsigned char * unsafe) uip_conn->ripaddr,
                                     HTONS(uip_conn->lport),
                                     HTONS(uip_conn->rport),
                                     uip_conn);
    }
    enqueue_event_and_notify(client_num, XTCP_NEW_CONNECTION, xtcp_conn, NULL);
  }

  // Store data in rx_buffer and raise guard on MII/MAC interfaces
  if (uip_newdata() && uip_len > 0) {
    buffer_full = 1;
    xtcp_conn->packet_length = uip_len;
    memcpy(rx_buffer, uip_appdata, uip_len);
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_RECV_DATA, xtcp_conn, NULL);
  }

  else if (uip_timedout()) {
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_TIMED_OUT, xtcp_conn, NULL);
    return;
  }

  else if (uip_aborted()) {
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_ABORTED, xtcp_conn, NULL);
    return;
  }

  if (uip_acked()) {
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_SENT_DATA, xtcp_conn, NULL);
  }

  if (uip_rexmit()) {
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_RESEND_DATA, xtcp_conn, NULL);
  }

  if (uip_poll()) {
    // Currently does nothing
  }

  if (uip_closed()) {
    enqueue_event_and_notify(xtcp_conn->client_num, XTCP_CLOSED, xtcp_conn, NULL);
  }
}
