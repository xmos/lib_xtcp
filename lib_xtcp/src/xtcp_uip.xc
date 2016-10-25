// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xtcp.h"
#include <string.h>
#include <smi.h>
#include <xassert.h>
#include <print.h>
#include <malloc.h>
/* Used to prevent conflict with uIP */
#include "xtcp_uip_includes.h"
#include <debug_print.h>

#define ETHBUF ((struct uip_eth_hdr   * unsafe) &uip_buf[0])
#define UDPBUF ((struct uip_udpip_hdr * unsafe) &uip_buf[UIP_LLH_LEN])

#define NO_CLIENT -1

typedef struct listener_info_t {
  unsigned active;
  unsigned port_number;
  int client_num; /* Can be NO_CLIENT */
} listener_info_t;

listener_info_t tcp_listeners[NUM_TCP_LISTENERS] = {{0}};
listener_info_t udp_listeners[NUM_UDP_LISTENERS] = {{0}};

unsafe void inline xtcp_if_up(void);

#if UIP_USE_DHCP
unsafe void 
dhcpc_configured(const struct dhcpc_state * unsafe s) {
#if UIP_USE_AUTOIP
  uip_autoip_stop();
#endif
  uip_sethostaddr(s->ipaddr);
  uip_setdraddr(s->default_router);
  uip_setnetmask(s->netmask);
  xtcp_if_up();
}
#endif

static int 
get_listener_linknum(listener_info_t listeners[],
                     int n_ports,
                     int local_port)
{
  int client_num = NO_CLIENT;
  for (unsigned i=0; i<n_ports; i++) {
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
  for (unsigned i=0; i<n_ports; i++) {
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
  unsigned i;
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

void uip_linkdown(void )
{
#if UIP_USE_DHCP
  dhcpc_stop();
#endif
#if UIP_USE_AUTOIP
  uip_autoip_stop();
#endif
}

/* uIP global variables */
extern unsigned short uip_len;     /* Length of data in buffer */
extern unsigned short uip_slen;    /* Length of data to be sent in buffer */
extern void * unsafe uip_sappdata; /* Pointer to start position of data in packet buffer */
unsigned int uip_buf32[(UIP_BUFSIZE + 5) >> 2];  /* uIP buffer in 32bit words */
unsafe {
  u8_t * unsafe uip_buf = (u8_t *) &uip_buf32[0];/* uIP buffer 8bit */
}

/* Extra buffer to hold data until the client is ready */
unsigned int rx_buffer[(UIP_BUFSIZE + 5) >> 2];

/* These pointers are used to store connections for 
   sending in xcoredev.xc */
extern client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx;
extern client interface mii_if * unsafe xtcp_i_mii;
extern mii_info_t xtcp_mii_info;

typedef struct client_queue_uip_t {
  xtcp_event_type_t xtcp_event;
  struct xtcp_connection_t * unsafe conn;
  struct client_queue_uip_t * unsafe next;
} client_queue_uip_t;

static client_queue_uip_t * unsafe * unsafe client_queue;
typedef client_queue_uip_t * unsafe ptr_unsafe_client_queue_uip_t;
static server xtcp_if * unsafe xtcp_i_xtcp; /* Global variable of the xtcp interface. 
                                             * Used by the queueing mechanism */
static unsigned uip_static_ip = 0; /* Boolean whether we're using a static IP */
static unsigned n_xtcp;            /* Number of clients */
static unsigned buffer_full = 0;   /* Boolean whether the RX buffer is full */

static unsafe void 
xtcp_uip_init(xtcp_ipconfig_t* ipconfig, unsigned char mac_address[6]) {
  memcpy(&uip_ethaddr, mac_address, 6);
  uip_init();

#if UIP_IGMP
  igmp_init();
#endif

  if (ipconfig != NULL && (*((int*)ipconfig->ipaddr) != 0)) {
    uip_static_ip = 1;
  }

  uip_sethostaddr(ipconfig->ipaddr);
  uip_setdraddr(ipconfig->gateway);
  uip_setnetmask(ipconfig->netmask);

#if UIP_USE_AUTOIP
    int hwsum = mac_address[0] + mac_address[1] + mac_address[2] +
                mac_address[3] + mac_address[4] + mac_address[5];
    uip_autoip_init(hwsum + (hwsum << 16) + (hwsum << 24));
#endif
#if UIP_USE_DHCP
    dhcpc_init(uip_ethaddr.addr, 6);
#endif
}

static unsigned 
get_guid(void)
{
  static unsigned guid = 0;
  guid++;
  
  if(guid > 200) {
    guid = 0;
  }

  return guid;
}

static unsafe void
enqueue_event_and_notify(unsigned client_num,
                         xtcp_event_type_t xtcp_event,
                         xtcp_connection_t * unsafe conn)
{
  /* Create new event */
  client_queue_uip_t * unsafe event = (client_queue_uip_t * unsafe) malloc(sizeof(client_queue_uip_t));
  event->xtcp_event = xtcp_event;
  event->conn = conn;
  event->next = NULL;

  /* Queue empty */
  if(!client_queue[client_num]) {
    client_queue[client_num] = event;
  } else {
    /* Find tail */
    client_queue_uip_t * unsafe tail = client_queue[client_num];
    while(tail->next) {
      tail = tail->next;
    }
    tail->next = event;
  }

  /* Notify */
  xtcp_i_xtcp[client_num].packet_ready();
}

static unsafe client_queue_uip_t 
dequeue_event(unsigned client_num)
{
  /* Must be something to dequeue */
  xassert(client_queue[client_num]);
  /* Get next */
  client_queue_uip_t * unsafe next = client_queue[client_num]->next;
  /* Get data */
  client_queue_uip_t head = *client_queue[client_num];
  /* Free head */
  free(client_queue[client_num]);
  /* Reassign head */
  client_queue[client_num] = next;

  return head;
}

unsafe void
xtcp_if_up(void)
{
  xtcp_connection_t dummy;
  memset(&dummy, 0, sizeof(xtcp_connection_t));
  for(unsigned i=0; i<n_xtcp; i++) {
    enqueue_event_and_notify(i, XTCP_IFUP, &dummy);
  }
}

unsafe void
xtcp_if_down(void)
{
  xtcp_connection_t dummy;
  memset(&dummy, 0, sizeof(xtcp_connection_t));
  for(unsigned i=0; i<n_xtcp; i++) {
    enqueue_event_and_notify(i, XTCP_IFDOWN, &dummy);
  }
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
    uip_input(); /* Will eventually call xtcpd_appcall */
    if (uip_len > 0) {
      if (uip_udpconnection()) {
        uip_arp_out(uip_udp_conn);
      } else {
        uip_arp_out(NULL);
      }
      xtcp_tx_buffer();
    }
    /* ARP. No input for application */
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

static unsafe xtcp_connection_t
create_xtcp_state(int client_num,
                  xtcp_protocol_t protocol,
                  unsigned char * unsafe remote_addr,
                  int local_port,
                  int remote_port,
                  void * unsafe stack_conn)
{
  xassert(client_num >= 0 && client_num < n_xtcp);
  
  xtcp_connection_t conn = {0};
  
  conn.client_num = client_num;
  conn.id = get_guid();
  conn.protocol = protocol;
  for (int i=0; i<4; i++)
    conn.remote_addr[i] = remote_addr[i];
  conn.remote_port = remote_port;
  conn.local_port = local_port;
  conn.stack_conn = (int) stack_conn;

  return conn;
}

static unsafe void 
rm_recv_event_and_clear_buffer_flag(unsigned client_num)
{
  client_queue_uip_t * unsafe tail = client_queue[client_num];
  client_queue_uip_t * unsafe temp;

  /* Head is recv */
  if(tail->xtcp_event == XTCP_RECV_DATA) {
    buffer_full = 0;
    dequeue_event(client_num);
  }

  /* It could be elsewhere in the queue */
  while(tail && tail->next) {
    if(tail->next->xtcp_event == XTCP_RECV_DATA) {
      /* Chuck data */
      buffer_full = 0;
      /* Get event after next event */
      temp = tail->next->next;
      /* Free offending link */
      free(tail->next);
      /* Rejoin ends */
      tail = temp;
    }
    tail = tail->next;
  }
}

static unsafe xtcp_connection_t * unsafe
get_and_set_appstate(xtcp_connection_t conn)
{
  xtcp_connection_t * unsafe xtcp_conn;
  if(conn.protocol == XTCP_PROTOCOL_UDP) {
    uip_udp_conn = (struct uip_udp_conn * unsafe) conn.stack_conn;
    // uip_conn = NULL;
    return &(uip_udp_conn->appstate);
  } else {
    uip_conn = (struct uip_conn * unsafe) conn.stack_conn;
    // uip_udp_conn = NULL;
    return &(uip_conn->appstate);
  }
}

void 
xtcp_uip(server xtcp_if i_xtcp[n_xtcp_init], 
         static const unsigned n_xtcp_init,
         client mii_if ?i_mii,
         client ethernet_cfg_if ?i_eth_cfg,
         client ethernet_rx_if ?i_eth_rx,
         client ethernet_tx_if ?i_eth_tx,
         client smi_if ?i_smi,
         uint8_t phy_address,
         const char (&?mac_address0)[6],
         otp_ports_t &?otp_ports,
         xtcp_ipconfig_t &ipconfig)
{
  /* Entire function declared unsafe */
  unsafe {
  
  ptr_unsafe_client_queue_uip_t client_queue_init[n_xtcp_init];
  client_queue = client_queue_init;
  xtcp_i_xtcp = i_xtcp;
  n_xtcp = n_xtcp_init;

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

  if (!isnull(i_mii)) {
    mii_info = i_mii.init();
    xtcp_mii_info = mii_info;
    xtcp_i_mii = (client mii_if * unsafe) &i_mii;
  }

  if (!isnull(i_eth_cfg)) {
    xtcp_i_eth_tx = (client ethernet_tx_if * unsafe) &i_eth_tx;
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

  xtcp_uip_init(&ipconfig, mac_address);

  tmr :> timeout;
  timeout += 10000000;

  while (1) {
    select {
    /* Only accept new packets if there's nothing in the buffer already */
    case (!isnull(i_mii) && !buffer_full) => mii_incoming_packet(mii_info):
      int * unsafe data;
      int nbytes;
      unsigned timestamp;
      {data, nbytes, timestamp} = i_mii.get_incoming_packet();
      if (data) {
        if (nbytes <= UIP_BUFSIZE) {
          memcpy(uip_buf32, data, nbytes);
          xtcp_process_incoming_packet(nbytes);
        }
        i_mii.release_packet(data);
      }
      break;
    
    /* Only accept new packets if there's nothing in the buffer already */
    case (!isnull(i_eth_rx) && !buffer_full) => i_eth_rx.packet_ready():
      ethernet_packet_info_t desc;
      i_eth_rx.get_packet(desc, (char *) uip_buf32, UIP_BUFSIZE);
      if (desc.type == ETH_DATA) {
        xtcp_process_incoming_packet(desc.len);
      } else if (isnull(i_smi) && desc.type == ETH_IF_STATUS) {
        if (((unsigned char *)uip_buf32)[0] == ETHERNET_LINK_UP) {
          uip_linkup();
        }
        else {
          uip_linkdown();
        }
      }
      break;

    case i_xtcp[int i].listen(int port_number, xtcp_protocol_t protocol):
      if (protocol == XTCP_PROTOCOL_TCP) {
        uip_listen(HTONS(port_number));
        register_listener(tcp_listeners, i, HTONS(port_number), NUM_TCP_LISTENERS);
      } else {
        uip_udp_listen(HTONS(port_number));
        register_listener(udp_listeners, i, HTONS(port_number), NUM_UDP_LISTENERS);
      }
      break;

    case i_xtcp[int i].unlisten(unsigned port_number):
        uip_unlisten(HTONS(port_number));
        unregister_listener(tcp_listeners, i, HTONS(port_number), NUM_TCP_LISTENERS);
        
        uip_udp_unlisten(HTONS(port_number));
        unregister_listener(udp_listeners, i, HTONS(port_number), NUM_UDP_LISTENERS);
      break;

    /* Client calls get_packet after the server has notified */
    case i_xtcp[int i].get_packet(xtcp_connection_t &conn, char data[n], unsigned int n, unsigned &length):
      client_queue_uip_t head = dequeue_event(i);
      head.conn->event = head.xtcp_event;
      memcpy(&conn, head.conn, sizeof(xtcp_connection_t));
      length = 0;

      if(head.xtcp_event == XTCP_RECV_DATA) {
        memcpy(data, rx_buffer, head.conn->packet_length);
        buffer_full = 0;
        length = head.conn->packet_length;
      }

      /* More things on the queue */
      if(client_queue[i]) {
        i_xtcp[i].packet_ready();
      }
      break;
    
    case i_xtcp[int i].close(xtcp_connection_t conn):
      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);

      if (uip_udpconnection()) {
        uip_udp_conn->lport = 0;
        enqueue_event_and_notify(conn.client_num, XTCP_CLOSED, xtcp_conn);
      } else {
        uip_close();
      }
      break;
    
    case i_xtcp[int i].abort(xtcp_connection_t conn):
      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);
      rm_recv_event_and_clear_buffer_flag(conn.client_num);

      if (uip_udpconnection()) {
        uip_udp_conn->lport = 0;
        enqueue_event_and_notify(conn.client_num, XTCP_CLOSED, xtcp_conn);
      } else {
        uip_abort();
        uip_process(UIP_TCP_SEND);
        enqueue_event_and_notify(conn.client_num, XTCP_ABORTED, xtcp_conn);
      }
      break;

    case i_xtcp[int i].bind_local_udp(xtcp_connection_t conn, unsigned port_number):
      if (conn.protocol == XTCP_PROTOCOL_TCP) break;

      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);
      xtcp_conn->local_port = port_number;
      ((struct uip_udp_conn *) xtcp_conn->uip_conn)->lport = HTONS(port_number);
      break;

    case i_xtcp[int i].bind_remote_udp(xtcp_connection_t conn, xtcp_ipaddr_t ipaddr, unsigned port_number):
      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);

      if(conn.protocol == XTCP_PROTOCOL_TCP) break;

      /* Change ports for xtcp_conn and uip_idp_conn */
      uip_udp_conn->rport = HTONS(port_number);
      xtcp_conn->remote_port = port_number;

      /* The same for the IP address */
      XTCP_IPADDR_CPY(xtcp_conn->remote_addr, ipaddr);
      uip_udp_conn->ripaddr[0] = (ipaddr[1] << 8) | ipaddr[0];
      uip_udp_conn->ripaddr[1] = (ipaddr[3] << 8) | ipaddr[2];
      break;
    
    case i_xtcp[int i].connect(unsigned port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol):
      uip_ipaddr_t uipaddr;
      uip_ipaddr(uipaddr, ipaddr[0], ipaddr[1], ipaddr[2], ipaddr[3]);
      xtcp_connection_t xtcp_conn;
      
      if (protocol == XTCP_PROTOCOL_TCP) {
        struct uip_conn * unsafe conn = uip_connect(&uipaddr, HTONS(port_number));
        if (conn != NULL) {
          register_listener(tcp_listeners, i, conn->lport, NUM_TCP_LISTENERS);
          xtcp_conn = create_xtcp_state(i,
                                        XTCP_PROTOCOL_TCP,
                                        (unsigned char * unsafe) uipaddr,
                                        conn->lport,
                                        port_number,
                                        conn);
          conn->appstate = xtcp_conn;
        }
      } else {
        struct uip_udp_conn * unsafe conn = uip_udp_new(&uipaddr, HTONS(port_number));
        if (conn != NULL) {
          register_listener(udp_listeners, i, conn->lport, NUM_UDP_LISTENERS);
          xtcp_conn = create_xtcp_state(i,
                                        XTCP_PROTOCOL_UDP,
                                        (unsigned char * unsafe) uipaddr,
                                        conn->lport,
                                        port_number,
                                        conn);
          conn->appstate = xtcp_conn;
          enqueue_event_and_notify(i, XTCP_NEW_CONNECTION, &(conn->appstate));
        }
      }
      break;

    case i_xtcp[int i].send(xtcp_connection_t conn, char data[], unsigned len):
      if(!len) break; /* Nothing to send */

      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);

      /* Make sure we're writing to the correct place */
      if(conn.protocol == XTCP_PROTOCOL_UDP) {
        uip_sappdata = uip_appdata = &uip_buf[UIP_LLH_LEN + UIP_IPUDPH_LEN];
      } else {
        uip_sappdata = uip_appdata = &uip_buf[UIP_LLH_LEN + UIP_IPTCPH_LEN];
      }

      memcpy(uip_sappdata, data, len);
      uip_send(uip_sappdata, len);

      if (conn.protocol == XTCP_PROTOCOL_TCP) {
        uip_process(UIP_TCP_SEND); /* Hack? */
        uip_arp_out(NULL);
      } else {
        uip_process(UIP_UDP_SEND_CONN);
        uip_arp_out(uip_udp_conn);
        enqueue_event_and_notify(conn.client_num, XTCP_SENT_DATA, xtcp_conn);
      }
      xtcp_tx_buffer();
      break;

    case i_xtcp[int i].join_multicast_group(xtcp_ipaddr_t addr):
  #if UIP_IGMP
      uip_ipaddr_t ipaddr;
      uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
      igmp_join_group(ipaddr);
  #endif
      break;
    
    case i_xtcp[int i].leave_multicast_group(xtcp_ipaddr_t addr):
  #if UIP_IGMP
      uip_ipaddr_t ipaddr;
      uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
      igmp_leave_group(ipaddr);
  #endif
      break;

    case i_xtcp[int i].set_appstate(xtcp_connection_t conn, xtcp_appstate_t appstate):
      xtcp_connection_t * unsafe xtcp_conn = get_and_set_appstate(conn);
      xtcp_conn->appstate = appstate;
      break;

    case i_xtcp[int i].request_host_by_name(const char hostname[]):
      /* NOT SUPPORTED BY uIP */
      break;

    case tmr when timerafter(timeout) :> timeout:
      timeout += 10000000;

      /* Check for the link state */
      if (!isnull(i_smi)) {
        static int linkstate = 0;
        ethernet_link_state_t status = smi_get_link_state(i_smi, phy_address);
        if (!status && linkstate) {
          if (!isnull(i_eth_cfg)) {
            i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
          }
          uip_linkdown();
        }
        if (status && !linkstate) {
          if (!isnull(i_eth_cfg)) {
            i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
          }
          uip_linkup();
        }
        linkstate = status;
      }

      if (++arp_timer == 100) {
        arp_timer=0;
        uip_arp_timer();
      }

      // if (UIP_USE_AUTOIP) {
      //   if (++autoip_timer == 5) {
      //     autoip_timer = 0;
      //     uip_autoip_periodic();
      //     if (uip_len > 0) {
      //       xtcp_tx_buffer();
      //     }
      //   }
      // }

      xtcp_process_periodic_timer();
      break;
    }
  }
  } /* unsafe */
}

unsafe void 
xtcpd_appcall(void)
{
  xtcp_connection_t * unsafe conn;

  /* DHCP */
  if (uip_udpconnection() &&
      (uip_udp_conn->lport == HTONS(DHCPC_CLIENT_PORT) ||
       uip_udp_conn->lport == HTONS(DHCPC_SERVER_PORT))) {
#if UIP_USE_DHCP
    dhcpc_appcall();
#endif
    return;
  }

  /* Get connection state */
  if (uip_udpconnection()) {
    static int counter = 0;
    conn = (xtcp_connection_t * unsafe) &(uip_udp_conn->appstate);
    if (conn && uip_newdata()) {
      conn->remote_port = HTONS(UDPBUF->srcport);
      uip_ipaddr_copy(conn->remote_addr, UDPBUF->srcipaddr);
    }
  } else {
    xassert(uip_conn);
    conn = (xtcp_connection_t * unsafe) &(uip_conn->appstate);
  }

  /* New connection */
  if (uip_connected()) {
    if (uip_udpconnection()) {
      int client_num = get_listener_linknum(udp_listeners, 
                                            NUM_UDP_LISTENERS, 
                                            uip_udp_conn->lport);
      
      *conn = create_xtcp_state(client_num,
                                XTCP_PROTOCOL_UDP,
                                (unsigned char * unsafe) UDPBUF->srcipaddr,
                                uip_udp_conn->lport,
                                HTONS(UDPBUF->srcport),
                                uip_udp_conn);
    } else { 
      int client_num = get_listener_linknum(tcp_listeners,
                                            NUM_TCP_LISTENERS, 
                                            uip_conn->lport);
      
      *conn = create_xtcp_state(client_num,
                                XTCP_PROTOCOL_TCP,
                                (unsigned char * unsafe) uip_conn->ripaddr,
                                uip_conn->lport,
                                uip_conn->rport,
                                uip_conn);
    }
    enqueue_event_and_notify(conn->client_num, XTCP_NEW_CONNECTION, conn);
  }

  /* Store data in rx_buffer and stop packets incoming on either MII or MAC Ethernet */
  if (uip_newdata() && uip_len > 0) {
    buffer_full = 1;
    conn->packet_length = uip_len;
    memcpy(rx_buffer, uip_appdata, uip_len);
    enqueue_event_and_notify(conn->client_num, XTCP_RECV_DATA, conn);
  }

  else if (uip_timedout()) {
    enqueue_event_and_notify(conn->client_num, XTCP_TIMED_OUT, conn);
    return;
  }

  else if (uip_aborted()) {
    enqueue_event_and_notify(conn->client_num, XTCP_ABORTED, conn);
    return;
  }

  if (uip_acked()) {
    enqueue_event_and_notify(conn->client_num, XTCP_SENT_DATA, conn);
  }

  if (uip_rexmit()) {
    enqueue_event_and_notify(conn->client_num, XTCP_RESEND_DATA, conn);
  }

  if(uip_poll()) {
    /* Not sure if anything should happen here */
  }

  if (uip_closed()) {
    enqueue_event_and_notify(conn->client_num, XTCP_CLOSED, conn);
  }
}