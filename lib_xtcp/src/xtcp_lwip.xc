// Copyright (c) 2015-2016, XMOS Ltd, All rights reserved
#include "xc2compat.h"
#include <string.h>
#include <smi.h>
#include <xassert.h>
#include <malloc.h>
#include <print.h>
#include "xtcp.h"
/* Used to prevent conflict with lwIP */
#include "xtcp_lwip_includes.h"

#define MAX_PACKET_BYTES 1518

// These pointers are used to store connections for sending in
// xcoredev.xc
extern client interface ethernet_tx_if  * unsafe xtcp_i_eth_tx;
extern client interface mii_if * unsafe xtcp_i_mii;
extern mii_info_t xtcp_mii_info;

static void 
xtcp_lwip_low_level_init(struct netif &netif, char mac_address[6])
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

static void 
xtcp_lwip_init_timers(unsigned period[NUM_TIMEOUTS],
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

static unsafe void
process_rx_packet(char buffer[], size_t n_bytes,
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
  struct xtcp_connection_t conn;
} client_queue_t;

#define QUEUE_SIZE 10

static client_queue_t * unsafe client_queue;
static unsigned * unsafe client_heads;
static unsigned * unsafe client_num_events;
static server xtcp_if * unsafe xtcp_i_xtcp;

static unsafe void
enqueue_event_and_notify(unsigned client_num,
                         xtcp_event_type_t xtcp_event,
                         struct tcp_pcb * unsafe t_pcb,
                         struct udp_pcb * unsafe u_pcb,
                         struct pbuf *unsafe pbuf,
                         xtcp_connection_t conn)
{
  /* Create new event */
  client_queue_t event;
  event.xtcp_event = xtcp_event;
  event.t_pcb = t_pcb;
  event.u_pcb = u_pcb;
  event.pbuf = pbuf;
  conn.event = xtcp_event;
  event.conn = conn;

  unsigned new_position = (client_heads[client_num] + client_num_events[client_num]) % QUEUE_SIZE;
  unsigned new_offset = (client_num * QUEUE_SIZE) + new_position;
  *(client_queue + new_offset) = event;

  client_num_events[client_num]++;
  xassert(client_num_events[client_num] <= QUEUE_SIZE);

  /* Notify */
  xtcp_i_xtcp[client_num].packet_ready();
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

static inline unsafe void
remove_pcb_udp_connection(struct udp_pcb * unsafe pcb,
                          unsigned slot)
{
  for (int i=0; i<4; i++) {
    pcb->connection_addrs[slot][i] = 0;
  }
  pcb->connection_ports[slot] = 0;
}

static inline unsafe unsigned
pcb_contains_connection(struct udp_pcb * unsafe pcb, 
                        unsigned char * unsafe addr, 
                        unsigned port_number)
{
  for(int i=0; i<CONNECTIONS_PER_UDP_PORT; i++) {
    if(pcb->connection_ports[i] == port_number &&
       XTCP_IPADDR_CMP(pcb->connection_addrs[i], addr)) {
      return 1;
    }
  }
  return 0;
}

static inline unsafe int
first_empty_pcb_udp_slot(struct udp_pcb * unsafe pcb) {
  for(int i=0; i<CONNECTIONS_PER_UDP_PORT; i++) {
    if(pcb->connection_ports[i] == 0) {
      return i;
    }
  }
  return -1;
}

static unsafe unsigned
add_udp_connection(struct udp_pcb * unsafe pcb,
                   unsigned char * unsafe addr, 
                   unsigned port_number)
{
  if(!pcb_contains_connection(pcb, (unsigned char * unsafe) addr, port_number)) {
    int empty_slot = first_empty_pcb_udp_slot(pcb);
    if(empty_slot != -1) {
      pcb->connection_ports[empty_slot] = port_number;
      for (int i=0; i<4; i++) {
        pcb->connection_addrs[empty_slot][i] = ((unsigned char * unsafe) addr)[i];
      }
      return 1;
      // enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_NEW_CONNECTION, NULL, pcb, NULL, pcb->xtcp_conn);
    } else {
      fail("Reached maximum amount of remote UDP connections per PCB");
    }
  }
  return 0;
}

static unsafe xtcp_connection_t
create_xtcp_state(int xtcp_num,
                  xtcp_protocol_t protocol,
                  unsigned char * unsafe remote_addr,
                  int local_port,
                  int remote_port,
                  void * unsafe pcb)
{
  xtcp_connection_t xtcp_conn = {0};

  xtcp_conn.client_num = xtcp_num;
  xtcp_conn.id = get_guid();
  xtcp_conn.protocol = protocol;
  for (int i=0; i<4; i++)
    xtcp_conn.remote_addr[i] = remote_addr[i];
  xtcp_conn.remote_port = remote_port;
  xtcp_conn.local_port = local_port;
  /* Point to PCB that holds this structure in it */
  xtcp_conn.stack_conn = (int) pcb;
  return xtcp_conn;
}

static unsafe client_queue_t 
dequeue_event(unsigned client_num)
{
  client_num_events[client_num]--;
  xassert(client_num_events[client_num] >= 0);

  unsigned offset = (client_num * QUEUE_SIZE) + client_heads[client_num];
  client_heads[client_num] = (++client_heads[client_num] % QUEUE_SIZE);
  client_queue_t head_of_queue = *(client_queue + offset);
  return head_of_queue;
}

static unsafe void 
rm_next_recv_event(xtcp_connection_t xtcp_conn,
                   unsigned client_num)
{
  unsigned offset = (client_num * QUEUE_SIZE);
  for(int i=0; i<client_num_events[client_num]; i++) {
    unsigned place_in_queue = (client_heads[client_num] + i) % QUEUE_SIZE;
    client_queue_t current_queue_item = *(client_queue + (offset + place_in_queue));
    
    if(current_queue_item.xtcp_event == XTCP_RECV_DATA &&
       current_queue_item.conn.id == xtcp_conn.id) {
      pbuf_free(current_queue_item.pbuf);
      
      for(int j=i; j<client_num_events[client_num] - 1; j++) {
        unsigned place = (client_heads[client_num] + j) % QUEUE_SIZE;
        unsigned next_place = ++place % QUEUE_SIZE;
        *(client_queue + (offset + place)) = *(client_queue + (offset + next_place));
      }

      client_num_events[client_num]--;
      break;
    }
  }
}

static unsigned ifstate = 0;

unsafe void
xtcp_if_up(unsigned n_xtcp)
{
  ifstate = 1;
  xtcp_connection_t dummy = {0};
  for(unsigned i=0; i<n_xtcp; i++) {
    enqueue_event_and_notify(i, XTCP_IFUP, NULL, NULL, NULL, dummy);
  }
}

unsafe void
xtcp_if_down(unsigned n_xtcp)
{
  ifstate = 0;
  xtcp_connection_t dummy = {0};
  for(unsigned i=0; i<n_xtcp; i++) {
    enqueue_event_and_notify(i, XTCP_IFDOWN, NULL, NULL, NULL, dummy);
  }
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
  /* Entire function declared unsafe */
  unsafe {
  client_queue = (client_queue_t * unsafe) malloc(sizeof(client_queue_t) * n_xtcp * QUEUE_SIZE);
  memset(client_queue, 0, sizeof(client_queue_t) * n_xtcp * QUEUE_SIZE);

  /* Assign global variables */
  // client_queue = (client_queue_t * unsafe) malloc(sizeof(client_queue_t) * n_xtcp * QUEUE_SIZE);
  // client_queue_t client_queue_init[n_xtcp][QUEUE_SIZE];
  unsigned client_heads_init[n_xtcp] = {0};
  unsigned client_num_events_init[n_xtcp] = {0};
  
  // client_queue = client_queue_init;
  client_heads = client_heads_init;
  client_num_events = client_num_events_init;

  for(int i=0; i<n_xtcp; i++) {
    client_heads[i] = 0;
    client_num_events[i] = 0;
  }
  
  xtcp_i_xtcp = i_xtcp;

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

  netif = &my_netif;
  netif = netif_add(netif, &ipaddr, &netmask, &gateway, NULL);
  netif_set_default(netif);

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
          netif_set_link_up(netif);
        } else {
          netif_set_link_down(netif);
          xtcp_if_down(n_xtcp);
        }
      }
      break;
    
    case i_xtcp[int i].listen(int port_number, xtcp_protocol_t protocol):
      xtcp_connection_t blank_conn = {0};
      blank_conn.client_num = i;
      if (protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe pcb = tcp_new();
        tcp_bind(pcb, NULL, port_number);
        pcb = tcp_listen(pcb);
        pcb->xtcp_conn = blank_conn;
      } else {
        struct udp_pcb *unsafe pcb = udp_new();
        udp_bind(pcb, NULL, port_number);
        unsigned char blank_ip[4] = {0,0,0,0};
        memset(pcb->connection_ports, 0, sizeof(unsigned) * CONNECTIONS_PER_UDP_PORT);
        memset(pcb->connection_addrs, 0, sizeof(unsigned char) * CONNECTIONS_PER_UDP_PORT * 4);
        pcb->xtcp_conn = create_xtcp_state(i, XTCP_PROTOCOL_UDP,
                                           blank_ip,
                                           port_number, 0, pcb);
      }
      break;

    /* Same as listen, but doesn't create the UDP PCB */
    case i_xtcp[int i].bind_local_udp(xtcp_connection_t conn, unsigned port_number):
      if (conn.protocol == XTCP_PROTOCOL_TCP) break;
      struct udp_pcb *unsafe u_pcb = (struct udp_pcb * unsafe) conn.stack_conn;
      /* Rebind to new port */
      udp_bind(u_pcb, NULL, port_number);
      break;

    case i_xtcp[int i].bind_remote_udp(xtcp_connection_t conn, xtcp_ipaddr_t ipaddr, unsigned port_number):
      if (conn.protocol == XTCP_PROTOCOL_TCP) break;
      struct udp_pcb *unsafe u_pcb = (struct udp_pcb * unsafe) conn.stack_conn;
      
      xtcp_ipaddr_t ip;
      memcpy(ip, ipaddr, sizeof(xtcp_ipaddr_t));
      unsigned port_n = port_number;
      
      err_t e = udp_connect(u_pcb, (struct ip_addr * unsafe) ip, port_n);
      if(e != ERR_OK)
        debug_printf("udp_connect() failed\n");
      add_udp_connection(u_pcb, ip, port_n);
      break;

    case i_xtcp[int i].unlisten(unsigned port_number):
      /* Need to make sure we've found all associated PCBs with port */
      int all_pcbs_found = 0;
      while(!all_pcbs_found) {
        struct tcp_pcb * unsafe t_pcb = xtcp_lookup_tcp_pcb_state_from_port(port_number);
        if(t_pcb) {
          tcp_abort(t_pcb);
        } else {
          struct udp_pcb * unsafe u_pcb = xtcp_lookup_udp_pcb_state_from_port(port_number);
          if(u_pcb) {
            udp_remove(u_pcb);
          } else {
            all_pcbs_found = 1;
          }
        }
      }
      break;

    /* Client calls get_packet after the server has notified */
    case i_xtcp[int i].get_packet(xtcp_connection_t &conn, char data[n], unsigned int n, unsigned &length):
      client_queue_t head = dequeue_event(i);
      memcpy(&conn, &head.conn, sizeof(xtcp_connection_t));
      unsigned bytecount = 0;

      if(head.xtcp_event == XTCP_RECV_DATA) {
        bytecount = head.pbuf->tot_len;
        struct pbuf *unsafe pb;
        unsigned offset = 0;
        
        for (pb = head.pbuf, offset = 0; pb != NULL; offset += pb->len, pb = pb->next) {
          memcpy(data + offset, pb->payload, pb->len);
        }
        
        if(head.conn.protocol == XTCP_PROTOCOL_TCP) {
          tcp_recved(head.t_pcb, head.pbuf->tot_len);
        } else {
          // UDP
        }
        pbuf_free(head.pbuf);
      }

      length = bytecount;
      
      /* More things on the queue */
      if(client_num_events[i] > 0) {
        i_xtcp[i].packet_ready();
      }
      break;

    case i_xtcp[int i].close(xtcp_connection_t conn):
      xtcp_connection_t xtcp_conn;
      if(conn.protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe t_pcb = (struct tcp_pcb * unsafe) conn.stack_conn;
        xtcp_conn = t_pcb->xtcp_conn;
        tcp_close(t_pcb);
      } else {
        struct udp_pcb *unsafe u_pcb = xtcp_lookup_udp_pcb_state(conn.id);
        xtcp_conn = u_pcb->xtcp_conn;
        int slot = pcb_contains_connection(u_pcb, conn.remote_addr, conn.remote_port);
        if(slot != -1)
          remove_pcb_udp_connection(u_pcb, slot);
      }
      enqueue_event_and_notify(i, XTCP_CLOSED, NULL, NULL, NULL, xtcp_conn);
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
      xtcp_connection_t xtcp_conn;
      rm_next_recv_event(conn, i);
      if(conn.protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe t_pcb = (struct tcp_pcb *unsafe) conn.stack_conn;
        xtcp_conn = t_pcb->xtcp_conn;
        tcp_abort(t_pcb);
        enqueue_event_and_notify(i, XTCP_ABORTED, NULL, NULL, NULL, xtcp_conn);
      } else {
        struct udp_pcb *unsafe u_pcb = (struct udp_pcb *unsafe) conn.stack_conn;
        xtcp_conn = u_pcb->xtcp_conn;
        int slot = pcb_contains_connection(u_pcb, conn.remote_addr, conn.remote_port);
        if(slot != -1)
          remove_pcb_udp_connection(u_pcb, slot);
        enqueue_event_and_notify(i, XTCP_CLOSED, NULL, NULL, NULL, xtcp_conn);
      }
      break;

    case i_xtcp[int i].connect(unsigned port_number, xtcp_ipaddr_t ipaddr, xtcp_protocol_t protocol):
      xtcp_connection_t blank_conn = {0};
      blank_conn.client_num = i;

      xtcp_ipaddr_t ip;
      memcpy(ip, ipaddr, sizeof(xtcp_ipaddr_t));
      unsigned port_n = port_number;

      if (protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe pcb = tcp_new();
        tcp_connect(pcb, (struct ip_addr * unsafe) ip, port_n, NULL);
        pcb->xtcp_conn = blank_conn;
      } else {
        /* UDP is basically create, bind local and bind remote */
        struct udp_pcb *unsafe pcb = udp_new();
        udp_bind(pcb, NULL, port_n);
        unsigned char blank_ip[4] = {0,0,0,0};
        memset(pcb->connection_ports, 0, sizeof(unsigned) * CONNECTIONS_PER_UDP_PORT);
        memset(pcb->connection_addrs, 0, sizeof(unsigned char) * CONNECTIONS_PER_UDP_PORT * 4);
        pcb->xtcp_conn = create_xtcp_state(i, XTCP_PROTOCOL_UDP,
                                           blank_ip,
                                           port_n, 0, pcb);
        if(add_udp_connection(pcb, ip, port_n)) {
          enqueue_event_and_notify(i, XTCP_NEW_CONNECTION, NULL, pcb, NULL, pcb->xtcp_conn);
        }
      }
      break;

    case i_xtcp[int i].send(xtcp_connection_t conn, char data[], unsigned len):
      if(len <= 0) break;

      if(conn.protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb *unsafe t_pcb = (struct tcp_pcb *unsafe) conn.stack_conn;
        if(tcp_sndbuf(t_pcb) >= tcp_mss(t_pcb)) {
          char buffer[XTCP_MAX_RECEIVE_SIZE];
          memcpy(buffer, data, len);
          err_t e = tcp_write(t_pcb, buffer, len, TCP_WRITE_FLAG_COPY);
          if (e != ERR_OK)
            debug_printf("tcp_write() failed\n");
          tcp_output(t_pcb);
        }
      } else {
        struct udp_pcb *unsafe u_pcb = (struct udp_pcb *unsafe) conn.stack_conn;
        struct pbuf *unsafe new_pbuf = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
        memcpy(new_pbuf->payload, data, len);

        err_t e;
        if (u_pcb->flags & UDP_FLAGS_CONNECTED) {
          e = udp_send(u_pcb, new_pbuf);
        } else {
          e = udp_sendto(u_pcb, new_pbuf, (ip_addr_t * unsafe) conn.remote_addr, conn.remote_port);
        }
        pbuf_free(new_pbuf);
        if (e != ERR_OK)
          debug_printf("udp_send() failed\n");
      }
      break;

    case i_xtcp[int i].set_appstate(xtcp_connection_t conn, xtcp_appstate_t appstate):
      if(conn.protocol == XTCP_PROTOCOL_TCP) {
        struct tcp_pcb * unsafe t_pcb = (struct tcp_pcb * unsafe) conn.stack_conn;
        t_pcb->xtcp_conn.appstate = appstate;
      } else {
        struct udp_pcb * unsafe u_pcb = (struct udp_pcb * unsafe) conn.stack_conn;
        u_pcb->xtcp_conn.appstate = appstate;
      }
      break;

    case i_xtcp[int i].request_host_by_name(const char hostname[], unsigned name_len):
      struct dns_table_entry *unsafe dns;
      int table_entry;
      if (name_len >= DNS_MAX_NAME_LENGTH)
        fail("DNS host name len exceeds DNS_MAX_NAME_LENGTH");
      dns = dns_find_entry(&table_entry);
      if(dns) {
        memcpy(dns->name, hostname, name_len+1);
        dns_enqueue(name_len, (void *)i, table_entry);
      }
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

            xtcp_if_down(n_xtcp);
            netif_set_link_down(netif);
          } else if (status && !linkstate) {
            if (!isnull(i_eth_cfg))
              i_eth_cfg.set_link_state(0, status, LINK_100_MBPS_FULL_DUPLEX);
            netif_set_link_up(netif);
          }
          linkstate = status;
        }

        if(!ifstate) {
          if (dhcp_supplied_address(netif) ||
              using_fixed_ip) {
            xtcp_if_up(n_xtcp);
          }
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
  } /* Unsafe */
}

/* Function called by lwIP when any TCP event happens on a connection */
unsafe err_t
lwip_tcp_event(void *unsafe arg,
               struct tcp_pcb *unsafe pcb,
               enum lwip_event e,
               struct pbuf *unsafe p,
               u16_t size,
               err_t err)
{
  switch(e) {
    case LWIP_EVENT_ACCEPT:
    case LWIP_EVENT_CONNECTED:
      pcb->xtcp_conn = 
        create_xtcp_state(pcb->xtcp_conn.client_num, XTCP_PROTOCOL_TCP,
                          (unsigned char * unsafe) &pcb->remote_ip,
                          pcb->local_port, pcb->remote_port, pcb);
      enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_NEW_CONNECTION, pcb, NULL, NULL, pcb->xtcp_conn);
      break;

    case LWIP_EVENT_RECV:
      if(p != NULL) {
        enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_RECV_DATA, pcb, NULL, p, pcb->xtcp_conn);
      }
      break;

    case LWIP_EVENT_SENT:
      enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_SENT_DATA, pcb, NULL, NULL, pcb->xtcp_conn);
      break;

    case LWIP_EVENT_ERR: {
      debug_printf("LWIP_EVENT_ERR: %s\n", lwip_strerr(err));
      break;
    }
  }
  return ERR_OK;
}

/* Function called by lwIP when there is a DNS result */
unsafe void
lwip_xtcpd_handle_dns_response(ip_addr_t * unsafe ipaddr, int client_num)
{
  xtcp_connection_t dummy = {0};
  for (int i=0; i<4; i++)
    dummy.remote_addr[i] = ((unsigned char * unsafe) ipaddr)[i];
  enqueue_event_and_notify(client_num, XTCP_DNS_RESULT, NULL, NULL, NULL, dummy);
}

/* Function called by lwIP when any UDP event happens on a connection */
unsafe void 
udp_recv_event(void * unsafe arg, 
               struct udp_pcb * unsafe pcb, 
               struct pbuf * unsafe p,
               const ip_addr_t * unsafe addr,
               u16_t _port) /* The underscore prefix is added by xtcp_lwip_includes */
{
  switch (_port) {
    case DHCP_CLIENT_PORT:
    case DHCP_SERVER_PORT:
      dhcp_recv(arg, pcb, p, addr, _port);
      break;
    case DNS_SERVER_PORT:
      dns_recv(arg, pcb, p, addr, _port);
      break;
    default:
      if (pcb == NULL) {
        pbuf_free(p);
        break;
      } else {
        /* Update xtcp_conn */
        pcb->xtcp_conn.remote_port = _port;
        for (int i=0; i<4; i++) {
          pcb->xtcp_conn.remote_addr[i] = ((unsigned char * unsafe) addr)[i];
        }

        if(add_udp_connection(pcb, (unsigned char * unsafe) addr, _port)) {
          enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_NEW_CONNECTION, NULL, pcb, NULL, pcb->xtcp_conn);
        }
        
        if (p != NULL)
          enqueue_event_and_notify(pcb->xtcp_conn.client_num, XTCP_RECV_DATA, NULL, pcb, p, pcb->xtcp_conn);
      }
      break;
  }
}
