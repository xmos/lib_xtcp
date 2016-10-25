// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xc2compat.h"
#include <string.h>
#include <smi.h>
#include <xassert.h>
#include <malloc.h>
#include <print.h>
#include "xtcp.h"
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "netif/etharp.h"
#include "lwip/autoip.h"
#include "lwip/init.h"
#include "lwip/tcp.h"
#include "lwip/tcp_impl.h"
#include "lwip/igmp.h"
#include "lwip/dhcp.h"
#include "lwip/dns.h"

#define MAX_PACKET_BYTES 1518

// These pointers are used to store connections for sending in
// xcoredev.xc
extern client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx;
extern client interface mii_if * unsafe xtcp_i_mii;
extern mii_info_t xtcp_mii_info;

extern "C" {
  struct tcp_pcb *xtcp_lookup_tcp_pcb_state(int conn_id);
}

void xtcp_lwip_low_level_init(struct netif &netif, char mac_address[6])
{
  /* set MAC hardware address length */
  netif.hwaddr_len = ETHARP_HWADDR_LEN;
  /* set MAC hardware address */
  memcpy(netif.hwaddr, mac_address, ETHARP_HWADDR_LEN);
  /* maximum transfer unit */
  netif.mtu = 1500;
  /* device capabilities */
  netif.flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_UP;
}

void xtcp_lwip_init_timers(unsigned period[NUM_TIMEOUTS],
                           unsigned timeout[NUM_TIMEOUTS],
                           unsigned time_now)
{
  period[ARP_TIMEOUT] = ARP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[AUTOIP_TIMEOUT] = AUTOIP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[TCP_TIMEOUT] = TCP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[IGMP_TIMEOUT] = IGMP_TMR_INTERVAL * XS1_TIMER_KHZ;
  period[DHCP_COARSE_TIMEOUT] = DHCP_COARSE_TIMER_MSECS * XS1_TIMER_KHZ;
  period[DHCP_FINE_TIMEOUT] = DHCP_FINE_TIMER_MSECS * XS1_TIMER_KHZ;

  for (int i=0; i < NUM_TIMEOUTS; i++) {
    timeout[i] = time_now + period[i];
  }
}

static unsafe void process_rx_packet(char buffer[], size_t n_bytes,
  struct netif *unsafe netif)
{
  struct pbuf *unsafe p, *unsafe q;
  if (ETH_PAD_SIZE) {
    n_bytes += ETH_PAD_SIZE; /* allow room for Ethernet padding */
  }
  /* We allocate a pbuf chain of pbufs from the pool. */
  p = pbuf_alloc(PBUF_RAW, n_bytes, PBUF_POOL);

  if (p != NULL) {
    if (ETH_PAD_SIZE) {
      pbuf_header(p, -ETH_PAD_SIZE); /* drop the padding word */
    }
    /* We iterate over the pbuf chain until we have read the entire
     * packet into the pbuf. */
    unsigned byte_cnt = 0;
    for (q = p; q != NULL; q = q->next) {
      /* Read enough bytes to fill this pbuf in the chain. The
       * available data in the pbuf is given by the q->len
       * variable. */
      memcpy(q->payload, (char *unsafe)&buffer[byte_cnt], q->len);
      byte_cnt += q->len;
    }

    if (ETH_PAD_SIZE) {
      pbuf_header(p, ETH_PAD_SIZE); /* reclaim the padding word */
    }

    ethernet_input(p, netif); // Process the packet
  } else {
    debug_printf("No buffers free\n");
  }
}

typedef struct client_queue_t {
  xtcp_event_type_t xtcp_event;
  struct tcp_pcb *unsafe t_pcb;           /* Could be null */
  struct udp_pcb *unsafe u_pcb;           /* Could be null */
  struct pbuf *unsafe pbuf;               /* Could be null */
  struct xtcp_connection_t *unsafe conn;
  struct client_queue_t *unsafe next;
} client_queue_t;

static client_queue_t * unsafe client_queue[2];
static server xtcp_if * unsafe xtcp_i_xtcp;

unsafe void
enqueue_event_and_notify(unsigned client_num,
                         xtcp_event_type_t xtcp_event,
                         struct tcp_pcb * unsafe t_pcb,
                         struct udp_pcb * unsafe u_pcb,
                         struct pbuf *unsafe pbuf,
                         xtcp_connection_t * unsafe conn)
{
  /* Create new event */
  client_queue_t * unsafe event = (client_queue_t * unsafe) malloc(sizeof(client_queue_t));
  event->xtcp_event = xtcp_event;
  event->t_pcb = t_pcb;
  event->u_pcb = u_pcb;
  event->pbuf = pbuf;
  event->conn = conn;
  event->next = NULL;

  /* Queue empty */
  if(!client_queue[client_num]) {
    client_queue[client_num] = event;
  } else {
    /* Find tail */
    client_queue_t *unsafe tail = client_queue[client_num];
    while(tail->next != 0) {
      tail = tail->next;
    }
    tail->next = event;
  }

  /* Notify */
  xtcp_i_xtcp[client_num].packet_ready();
}

unsafe client_queue_t 
dequeue_event(unsigned client_num)
{
  /* Must be something to dequeue */
  xassert(client_queue[client_num]);
  /* Get next */
  client_queue_t * unsafe next = client_queue[client_num]->next;
  /* Get data */
  client_queue_t head = *client_queue[client_num];
  /* Free head */
  free(client_queue[client_num]);
  /* Reassign head */
  client_queue[client_num] = next;

  return head;
}

unsafe void inline
xtcp_if_up(struct netif *unsafe netif,
           unsigned n_xtcp)
{
  netif_set_link_up(netif);
  xtcp_connection_t dummy;
  memset(&dummy, 0, sizeof(xtcp_connection_t));
  for(unsigned i=0; i<n_xtcp; i++)
    enqueue_event_and_notify(i, XTCP_IFUP, NULL, NULL, NULL, &dummy);
}

unsafe void inline
xtcp_if_down(struct netif *unsafe netif,
             unsigned n_xtcp)
{
  netif_set_link_down(netif);
  xtcp_connection_t dummy;
  memset(&dummy, 0, sizeof(xtcp_connection_t));
  for(unsigned i=0; i<n_xtcp; i++)
    enqueue_event_and_notify(i, XTCP_IFDOWN, NULL, NULL, NULL, &dummy);
}

void 
xtcp_lwip(server xtcp_if i_xtcp[n_xtcp], 
          static const unsigned n_xtcp,
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
  unsafe {
    // client_queue = (client_queue_t * unsafe * unsafe) malloc(sizeof(client_queue_t) * n_xtcp);
    // client_queue_t * unsafe client_queue_init[n_xtcp];
    // client_queue = client_queue_init;
    // client_queue = client_queue_init;
    // for(int i=0; i<n_xtcp; i++)
    //   client_queue[i] = NULL;
    xtcp_i_xtcp = i_xtcp;
    // xtcp_init(client_queue_init, i_xtcp, n_xtcp);
  }

  mii_info_t mii_info;
  timer timers[NUM_TIMEOUTS];
  unsigned timeout[NUM_TIMEOUTS];
  unsigned period[NUM_TIMEOUTS];

  char mac_address[6];
  struct netif my_netif;
  struct netif *unsafe netif;

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
    unsafe {
      xtcp_i_mii = (client mii_if * unsafe) &i_mii;
    }
  }

  if (!isnull(i_eth_cfg)) {
    unsafe {
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
  }

  int using_fixed_ip = 0;
  for (int i = 0; i < sizeof(ipconfig.ipaddr); i++) {
    if (((unsigned char *)ipconfig.ipaddr)[i]) {
      using_fixed_ip = 1;
      break;
    }
  }

  lwip_init();

  ip4_addr_t ipaddr, netmask, gateway;
  memcpy(&ipaddr, ipconfig.ipaddr, sizeof(xtcp_ipaddr_t));
  memcpy(&netmask, ipconfig.netmask, sizeof(xtcp_ipaddr_t));
  memcpy(&gateway, ipconfig.gateway, sizeof(xtcp_ipaddr_t));

  unsafe {
    netif = &my_netif;
    netif = netif_add(netif, &ipaddr, &netmask, &gateway, NULL);
    netif_set_default(netif);
  }

  /* Function needs to be called after netif_add (which zeroes everything). */
  xtcp_lwip_low_level_init(my_netif, mac_address);

  if (ipconfig.ipaddr[0] == 0) {
    if (dhcp_start(netif) != ERR_OK) fail("DHCP error");
  }
  netif_set_up(netif);

  int time_now;
  timers[0] :> time_now;
  xtcp_lwip_init_timers(period, timeout, time_now);

  while (1) {
    unsafe {
    select {
    case !isnull(i_mii) => mii_incoming_packet(mii_info):
      int * unsafe data;
      do {
        int nbytes;
        unsigned timestamp;
        {data, nbytes, timestamp} = i_mii.get_incoming_packet();
        if (data) {
          process_rx_packet((char *)data, nbytes, netif);
          i_mii.release_packet(data);
        }
      } while (data != NULL);
      break;
    
    case !isnull(i_eth_rx) => i_eth_rx.packet_ready():
      char buffer[MAX_PACKET_BYTES];
      ethernet_packet_info_t desc;
      i_eth_rx.get_packet(desc, (char *) buffer, MAX_PACKET_BYTES);

      if (desc.type == ETH_DATA) {
        process_rx_packet(buffer, desc.len, netif);
      }
      else if (isnull(i_smi) && desc.type == ETH_IF_STATUS) {
        if (((unsigned char *)buffer)[0] == ETHERNET_LINK_UP) {
          xtcp_if_up(netif, n_xtcp);
        } else {
          xtcp_if_down(netif, n_xtcp);
        }
      }
      break;
    
    case i_xtcp[int i].listen(int port_number, xtcp_protocol_t protocol):
      int *unsafe xtcp_num = (int * unsafe) malloc(sizeof(int));
      *xtcp_num = i;
      if (protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe pcb = tcp_new();
        tcp_bind(pcb, NULL, port_number);
        pcb = tcp_listen(pcb);
        tcp_arg(pcb, xtcp_num);
      } else {
        struct udp_pcb *unsafe pcb = udp_new();
        udp_bind(pcb, NULL, port_number);
        udp_arg(pcb, xtcp_num);
      }
      break;

    case i_xtcp[int i].bind_local_udp(xtcp_connection_t conn, unsigned port_number):
      break;

    case i_xtcp[int i].bind_remote_udp(xtcp_connection_t conn, xtcp_ipaddr_t ipaddr, unsigned port_number):
      break;

    /* No more connections on this port, EVER */
    case i_xtcp[int i].unlisten(unsigned port_number):
      // struct tcp_pcb * unsafe t_pcb = xtcp_lookup_tcp_pcb_state_from_port(port_number);
      // if(t_pcb) {
      //   free(t_pcb->callback_arg);
      //   tcp_abort(t_pcb);
      // } else {
        struct udp_pcb * unsafe u_pcb = xtcp_lookup_udp_pcb_state_from_port(port_number);
        xassert(u_pcb);
        free(u_pcb->recv_arg);
        udp_remove(u_pcb);
      // }
      break;

    /* Client calls get_packet after the server has notified */
    case i_xtcp[int i].get_packet(xtcp_connection_t &conn, char data[n], unsigned int n, unsigned &length):
      client_queue_t head = dequeue_event(i);
      head.conn->event = head.xtcp_event;
      memcpy(&conn, head.conn, sizeof(xtcp_connection_t));
      unsigned bytecount = 0;

      if(head.pbuf != NULL) {
        bytecount = head.pbuf->tot_len;
        struct pbuf *unsafe pb;
        unsigned offset = 0;
        
        for (pb = head.pbuf, offset = 0; pb != NULL; offset += pb->len, pb = pb->next) {
          memcpy(data + offset, pb->payload, pb->len);
        }
        
        if(head.t_pcb != NULL) {
          tcp_recved(head.t_pcb, head.pbuf->tot_len);
        } else {
          // UDP
        }
        pbuf_free(head.pbuf);
      }
      
      memcpy(&length, &bytecount, sizeof(unsigned));
      /* More things on the queue */
      if(client_queue[i] != NULL) {
        i_xtcp[i].packet_ready();
      }
      break;

    case i_xtcp[int i].close(xtcp_connection_t conn):
      struct tcp_pcb * unsafe t_pcb = xtcp_lookup_tcp_pcb_state(conn.id);
      if(t_pcb) {
        free(t_pcb->callback_arg);
        tcp_close(t_pcb); /* Can still recieve data, bugs ahead */
        /* Relisten */
      } else {
        struct udp_pcb * unsafe u_pcb = xtcp_lookup_udp_pcb_state(conn.id);
        xassert(u_pcb);
        // free(u_pcb->recv_arg);
        udp_disconnect(u_pcb);
      }
      enqueue_event_and_notify(i, XTCP_CLOSED, NULL, NULL, NULL, &conn);
      break;

    case i_xtcp[int i].join_multicast_group(xtcp_ipaddr_t addr):
      ip4_addr_t group_addr;
      memcpy(&group_addr, &addr, sizeof(ip4_addr_t));
      igmp_joingroup(IPADDR_ANY, &group_addr);
      break;

    case i_xtcp[int i].leave_multicast_group(xtcp_ipaddr_t addr):
      ip4_addr_t group_addr;
      memcpy(&group_addr, &addr, sizeof(ip4_addr_t));
      igmp_leavegroup(IPADDR_ANY, &group_addr);
      break;

    case i_xtcp[int i].abort(xtcp_connection_t conn):
      struct tcp_pcb * unsafe t_pcb = xtcp_lookup_tcp_pcb_state(conn.id);
      if(t_pcb) {
        // free(t_pcb->callback_arg);
        tcp_abort(t_pcb);
      } else {
        struct udp_pcb * unsafe u_pcb = xtcp_lookup_udp_pcb_state(conn.id);
        xassert(u_pcb);
        // free(u_pcb->recv_arg);
        udp_disconnect(u_pcb);
      }
      enqueue_event_and_notify(i, XTCP_ABORTED, NULL, NULL, NULL, &conn);
      break;

    case i_xtcp[int i].connect(unsigned port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol):
      break;

    case i_xtcp[int i].send_with_index(xtcp_connection_t conn, char data[], unsigned index, unsigned len):
      break;

    case i_xtcp[int i].send(xtcp_connection_t conn, char data[], unsigned len):
      char buffer[XTCP_MAX_RECEIVE_SIZE];

      struct tcp_pcb * unsafe t_pcb; 
      struct udp_pcb * unsafe u_pcb;

      t_pcb = xtcp_lookup_tcp_pcb_state(conn.id);
      if(t_pcb == NULL) {
       u_pcb = xtcp_lookup_udp_pcb_state(conn.id);
      }
      
      if(t_pcb != NULL && tcp_sndbuf(t_pcb) >= tcp_mss(t_pcb)) {
        memcpy(buffer, data, len);
        err_t e = tcp_write(t_pcb, buffer, len, TCP_WRITE_FLAG_COPY);
        /* Force data send */
        tcp_output(t_pcb);
      } else if (u_pcb != NULL) {
        struct pbuf * unsafe new_pbuf = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
        memcpy(new_pbuf->payload, data, len);
        /* Change here if changing udp_connect() */
        // err_t r = udp_sendto(u_pcb, new_pbuf, (unsigned char * unsafe) conn.remote_addr, conn.remote_port);
        err_t e = udp_send(u_pcb, new_pbuf);
        pbuf_free(new_pbuf);
        if (e != ERR_OK) {
          debug_printf("udp_send() failed\n");
        }
      }
      break;

    case i_xtcp[int i].set_appstate(xtcp_connection_t conn, xtcp_appstate_t appstate):
      struct tcp_pcb * unsafe t_pcb = xtcp_lookup_tcp_pcb_state(conn.id);
      if(t_pcb) {
        xtcp_connection_t * unsafe existing_conn = t_pcb->callback_arg;
        existing_conn->appstate = appstate;
      } else {
        struct udp_pcb * unsafe u_pcb = xtcp_lookup_udp_pcb_state(conn.id);
        xassert(u_pcb);
        xtcp_connection_t * unsafe existing_conn = u_pcb->recv_arg;
        existing_conn->appstate = appstate;
      }
      break;

    case i_xtcp[int i].request_host_by_name(const char hostname[]):
      break;

    case(size_t i = 0; i < NUM_TIMEOUTS; i++)
      timers[i] when timerafter(timeout[i]) :> unsigned current:

      switch (i) {
      case ARP_TIMEOUT: {
        etharp_tmr();
        if (!isnull(i_smi)) {
          static int linkstate = 0;
          ethernet_link_state_t status = smi_get_link_state(i_smi, phy_address);
          if (!status && linkstate) {
            if (!isnull(i_eth_cfg))
              i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
            xtcp_if_down(netif, n_xtcp);
          } else if (status && !linkstate) {
            if (!isnull(i_eth_cfg))
              i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
            xtcp_if_up(netif, n_xtcp);
          }
          linkstate = status;
        }
        break;
      }
      case AUTOIP_TIMEOUT: autoip_tmr(); break;
      case TCP_TIMEOUT: tcp_tmr(); break;
      case IGMP_TIMEOUT: igmp_tmr(); break;
      case DHCP_COARSE_TIMEOUT: dhcp_coarse_tmr(); break;
      case DHCP_FINE_TIMEOUT: dhcp_fine_tmr(); break;
      default: fail("Bad timer\n"); break;
      }

      timeout[i] = current + period[i];
      break;
    default:
      break;
    }
    }
  }
}

unsigned 
get_guid(void)
{
  static unsigned guid = 0;
  guid++;
  
  if(guid > 200) {
    guid = 0;
  }

  return guid;
}

unsafe xtcp_connection_t * unsafe
create_and_link_xtcp_state(int xtcp_num,
                           xtcp_protocol_t protocol,
                           unsigned char * unsafe remote_addr,
                           int local_port,
                           int remote_port)
{
  xtcp_connection_t *unsafe conn = (xtcp_connection_t * unsafe) malloc(sizeof(xtcp_connection_t));
  memset(conn, 0, sizeof(xtcp_connection_t));
  conn->client_num = xtcp_num;
  conn->id = get_guid();
  conn->protocol = protocol;
  for (int i=0; i<4; i++)
    conn->remote_addr[i] = remote_addr[i];
  conn->remote_port = remote_port;
  conn->local_port = local_port;
  return conn;
}

unsafe err_t
lwip_tcp_event(void *unsafe arg, /* xtcp_connection_t */
               struct tcp_pcb *unsafe pcb,
               enum lwip_event e,
               struct pbuf *unsafe p,
               u16_t size,
               err_t err)
{
  switch(e) {
    case LWIP_EVENT_ACCEPT:
    case LWIP_EVENT_CONNECTED:
      int *unsafe xtcp_num_ptr = (int * unsafe) arg;
      int xtcp_num = *xtcp_num_ptr;
      free(arg);

      xtcp_connection_t * unsafe conn = 
        create_and_link_xtcp_state(xtcp_num, XTCP_PROTOCOL_TCP,
                                   (unsigned char * unsafe) &pcb->remote_ip,
                                   pcb->local_port, pcb->remote_port);
      tcp_arg(pcb, conn);
      enqueue_event_and_notify(xtcp_num, XTCP_NEW_CONNECTION, pcb, NULL, NULL, conn);
      break;

    case LWIP_EVENT_RECV:
      xtcp_connection_t * unsafe conn = (xtcp_connection_t * unsafe) arg;
      enqueue_event_and_notify(conn->client_num, XTCP_RECV_DATA, pcb, NULL, p, conn);
      break;

    case LWIP_EVENT_SENT:
      xtcp_connection_t * unsafe conn = (xtcp_connection_t * unsafe) arg;
      enqueue_event_and_notify(conn->client_num, XTCP_SENT_DATA, pcb, NULL, NULL, conn);
      break;

    case LWIP_EVENT_ERR: {
      debug_printf("LWIP_EVENT_ERR: %s\n", lwip_strerr(err));
      break;
    }
  }
  return ERR_OK;
}

void lwip_xtcpd_handle_dns_response(ip_addr_t * unsafe ipaddr, int linknum) {}

unsafe void 
udp_recv_event(void * unsafe arg, 
               struct udp_pcb * unsafe pcb, 
               struct pbuf * unsafe p,
               const ip_addr_t * unsafe addr, 
               u16_t port)
{
  switch (port) {
    case DHCP_CLIENT_PORT:
    case DHCP_SERVER_PORT:
      dhcp_recv(arg, pcb, p, addr, port);
      break;
    case DNS_SERVER_PORT:
      dns_recv(arg, pcb, p, addr, port);
      break;
    default:
      if (pcb == NULL) {
        pbuf_free(p);
        break;
      } else {
        if ((pcb->flags & UDP_FLAGS_CONNECTED) == 0) {
          udp_connect(pcb, addr, port);
          int *unsafe xtcp_num_ptr = (int * unsafe) arg;
          int xtcp_num = *xtcp_num_ptr;
          free(arg);

          xtcp_connection_t * unsafe conn = 
            create_and_link_xtcp_state(xtcp_num, XTCP_PROTOCOL_UDP,
                                       (unsigned char * unsafe) addr,
                                       pcb->local_port, port);
          arg = conn;
          udp_arg(pcb, conn);
          enqueue_event_and_notify(xtcp_num, XTCP_NEW_CONNECTION, NULL, pcb, NULL, conn);
        }

        if (p != NULL) {
          xtcp_connection_t * unsafe conn = (xtcp_connection_t * unsafe) arg;
          enqueue_event_and_notify(conn->client_num, XTCP_RECV_DATA, NULL, pcb, p, conn);
        }
      }
      break;
  }
}
