// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include <xscope.h>
#include <string.h>
#include <print.h>
#include "uip.h"
#include "xtcp.h"
#include "xtcp_server.h"
#include "xtcp_server_impl.h"
#include "uip_timer.h"
#include "dhcpc.h"
#include "igmp.h"
#include "uip_arp.h"
#include "uip_xtcp.h"
#include "lwip/tcp.h"
#include "lwip/netif.h"
#include "lwip/dns.h"

#define DHCPC_SERVER_PORT  67
#define DHCPC_CLIENT_PORT  68


#ifndef NULL
#define NULL ((void *) 0)
#endif

#define MAX_GUID 200
static int guid = 1;

#if ((UIP_UDP_CONNS+UIP_CONNS) > MAX_GUID)
  #error "Cannot have more connections than GUIDs"
#endif

chanend *xtcp_links;
int xtcp_num;

#define NUM_TCP_LISTENERS 10
#define NUM_UDP_LISTENERS 10

struct listener_info_t {
  int active;
  int port_number;
  int linknum;
};


static int prev_ifstate[MAX_XTCP_CLIENTS];
struct listener_info_t tcp_listeners[NUM_TCP_LISTENERS] = {{0}};
struct listener_info_t udp_listeners[NUM_UDP_LISTENERS] = {{0}};

void xtcpd_init(chanend xtcp_links_init[], int n)
{
  int i;
  xtcp_links = xtcp_links_init;
  xtcp_num = n;
  for(i=0;i<MAX_XTCP_CLIENTS;i++)
    prev_ifstate[i] = -1;
  xtcpd_server_init();
}

__attribute__ ((noinline))
static int get_listener_linknum(struct listener_info_t listeners[],
                                int n,
                                int local_port)
{
  int i, linknum = -1;
  for (i=0;i<n;i++) {
    if (listeners[i].active &&
        local_port == listeners[i].port_number) {
      linknum = listeners[i].linknum;
      break;
    }
  }
  return linknum;
}


void xtcpd_init_state(xtcpd_state_t *s,
                      xtcp_protocol_t protocol,
                      xtcp_ipaddr_t remote_addr,
                      int local_port,
                      int remote_port,
                      void *conn) {
  int i;
  int linknum;
  int connect_request = s->s.connect_request;
  int connection_type = s->conn.connection_type;

  if (connect_request) {
    linknum = s->linknum;
  }
  else {
    connection_type = XTCP_SERVER_CONNECTION;
    if (protocol == XTCP_PROTOCOL_TCP) {
      linknum = get_listener_linknum(tcp_listeners, NUM_TCP_LISTENERS, local_port);
    }
    else {
      linknum = get_listener_linknum(udp_listeners, NUM_UDP_LISTENERS, local_port);
    }
  }

  memset(s, 0, sizeof(xtcpd_state_t));

  // Find and use a GUID that is not being used by another connection
  while (xtcpd_lookup_tcp_state(guid) != NULL)
  {
    guid++;
    if (guid > MAX_GUID)
      guid = 1;
  }

  s->conn.connection_type = connection_type;
  s->linknum = linknum;
  s->conn.id = guid;
  s->conn.local_port = local_port;
  s->conn.remote_port = remote_port;
  s->conn.protocol = protocol;
  s->s.uip_conn = (int) conn;
#ifdef XTCP_ENABLE_PARTIAL_PACKET_ACK
  s->s.accepts_partial_ack = 0;
#endif
  for (i=0;i<4;i++)
    s->conn.remote_addr[i] = remote_addr[i];
}


void xtcpd_event(xtcp_event_type_t event,
                 xtcpd_state_t *s)
{
  if (s->linknum != -1) {
    xtcpd_service_clients_until_ready(s->linknum, xtcp_links, xtcp_num);
    xtcpd_send_event(xtcp_links[s->linknum], event, s);
  }
}

static void unregister_listener(struct listener_info_t listeners[],
                                int linknum,
                                int port_number,
                                int n){

  int i;
  for (i=0;i<n;i++){
    if (listeners[i].port_number == port_number &&
        listeners[i].active) {
      listeners[i].active = 0;
    }
  }
}

static void register_listener(struct listener_info_t listeners[],
                              int linknum,
                              int port_number,
                              int n)
{
  int i;

  for (i=0;i<n;i++)
    if (!listeners[i].active)
      break;

  if (i==n) {
    // Error: max number of listeners reached
  }
  else {
    listeners[i].active = 1;
    listeners[i].port_number = port_number;
    listeners[i].linknum = linknum;
  }
}

void xtcpd_unlisten(int linknum, int port_number){
  unregister_listener(tcp_listeners, linknum, port_number, NUM_TCP_LISTENERS);
}

void xtcpd_listen(int linknum, int port_number, xtcp_protocol_t p)
{

  if (p == XTCP_PROTOCOL_TCP) {
    register_listener(tcp_listeners, linknum, port_number, NUM_TCP_LISTENERS);
    struct tcp_pcb *pcb = tcp_new();
    tcp_bind(pcb, NULL, port_number);
    tcp_listen(pcb);
  }
  else {
    register_listener(udp_listeners, linknum, port_number, NUM_UDP_LISTENERS);
    struct udp_pcb *pcb = udp_new();
    udp_bind(pcb, NULL, port_number);
  }
}


void xtcpd_bind_local(int linknum, int conn_id, int port_number)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  s->conn.local_port = port_number;
  if (s->conn.protocol == XTCP_PROTOCOL_UDP) {
    ((struct uip_udp_conn *) s->s.uip_conn)->lport = HTONS(port_number);
  } else {
    ((struct uip_conn *) s->s.uip_conn)->lport = HTONS(port_number);
  }
}

void xtcpd_bind_remote(int linknum,
                       int conn_id,
                       xtcp_ipaddr_t addr,
                       int port_number)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s->conn.protocol == XTCP_PROTOCOL_UDP) {
    struct uip_udp_conn *conn = (struct uip_udp_conn *) s->s.uip_conn;
    s->conn.remote_port = port_number;
    conn->rport = HTONS(port_number);
    XTCP_IPADDR_CPY(s->conn.remote_addr, addr);
    conn->ripaddr[0] = (addr[1] << 8) | addr[0];
    conn->ripaddr[1] = (addr[3] << 8) | addr[2];
  }
}

void xtcpd_connect(int linknum, int port_number, xtcp_ipaddr_t addr,
                   xtcp_protocol_t p) {
  if (p == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb *pcb = tcp_new();
    tcp_nagle_disable(pcb);
    ip_addr_t dst;
    IPADDR2_COPY(&dst, addr);
    err_t res = tcp_connect(pcb, &dst, port_number, NULL);
    if (res == ERR_OK) {
      xtcpd_state_t *s = (xtcpd_state_t *) &(pcb->xtcp_state);
      s->linknum = linknum;
      s->s.connect_request = 1;
      s->conn.connection_type = XTCP_CLIENT_CONNECTION;
      s->conn.protocol = XTCP_PROTOCOL_TCP;
    }
    else {
      fail("TCP connect failed");
    }
  }
  else {
    struct udp_pcb *pcb = udp_new();
    ip_addr_t dst;
    IPADDR2_COPY(&dst, addr);
    err_t res = udp_connect(pcb, &dst, port_number);
    if (res == ERR_OK) {
      xtcpd_state_t *s = (xtcpd_state_t *) &(pcb->xtcp_state);
      s->linknum = linknum;
      s->s.connect_request = 1;
      s->conn.connection_type = XTCP_CLIENT_CONNECTION;
      s->conn.protocol = XTCP_PROTOCOL_UDP;
    }
    else {
      fail("UDP connect failed");
    }
  }
}


void xtcpd_init_send(int linknum, int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);

  if (s != NULL) {
    s->s.send_request++;
  }
}


void xtcpd_init_send_from_uip(struct uip_conn *conn)
{
  xtcpd_state_t *s = &(conn->appstate);
  s->s.send_request++;
}

void xtcpd_set_appstate(int linknum, int conn_id, xtcp_appstate_t appstate)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    s->conn.appstate = appstate;
  }
}


void xtcpd_abort(int linknum, int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    s->s.abort_request = 1;
  }
}

void xtcpd_close(int linknum, int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    s->s.close_request = 1;
  }
}

void xtcpd_ack_recv_mode(int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    s->s.ack_recv_mode = 1;
  }
}

void xtcpd_ack_recv(int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    ((struct uip_conn *) s->s.uip_conn)->tcpstateflags &= ~UIP_STOPPED;
    s->s.ack_request = 1;
  }
}


void xtcpd_pause(int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    ((struct uip_conn *) s->s.uip_conn)->tcpstateflags |= UIP_STOPPED;
  }
}


void xtcpd_unpause(int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    ((struct uip_conn *) s->s.uip_conn)->tcpstateflags &= ~UIP_STOPPED;
    s->s.ack_request = 1;
  }
}

#ifdef XTCP_ENABLE_PARTIAL_PACKET_ACK
void xtcpd_accept_partial_ack(int conn_id)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL) {
    s->s.accepts_partial_ack = 1;
  }
}
#endif

extern u16_t uip_slen;

static int do_xtcpd_send(chanend c,
                  xtcp_event_type_t event,
                  xtcpd_state_t *s,
                  int mss)
{
  int len;

  xtcpd_service_clients_until_ready(s->linknum, xtcp_links, xtcp_num);
  len = xtcpd_send_split_start(c, event, s, mss);

  return len;
}



void lwip_xtcpd_handle_poll(xtcpd_state_t *s, struct tcp_pcb *pcb)
{
  if (s->s.send_request) {
    int len;
    xscope_int(TCP_SEND_BUF, tcp_sndbuf(pcb));
    if (s->linknum != -1 && (tcp_sndbuf(pcb) >= tcp_mss(pcb))) {
      len = do_xtcpd_send(xtcp_links[s->linknum],
                       XTCP_REQUEST_DATA,
                       s,
                       tcp_mss(pcb));
      if (len) {
        err_t r = tcp_write(pcb, (void *)xtcp_links[s->linknum], len, TCP_WRITE_FLAG_XCORE_CHAN_COPY);
        if (r != ERR_OK) fail("tcp_write() failed");
        tcp_output(pcb);
      }
      else {
        // Complete send
        // tcp_output(pcb);
      }
    }
    s->s.send_request--;
  }
}

void lwip_xtcpd_handle_dns_response(ip_addr_t *ipaddr, int linknum)
{
  xtcpd_state_t s; // This is hacky. We don't need a full state structure.
  memset(&s, 0, sizeof(xtcpd_state_t));
  s.linknum = linknum;
  if (ipaddr) {
    IPADDR2_COPY(&s.conn.remote_addr, ipaddr);
  }

  xtcpd_event(XTCP_DNS_RESULT, &s);
}

err_t lwip_tcp_event(void *arg, struct tcp_pcb *pcb,
         enum lwip_event e,
         struct pbuf *p,
         u16_t size,
         err_t err) {

  xassert(pcb != NULL);
  xtcpd_state_t *s = &(pcb->xtcp_state);

  switch (e) {
    case LWIP_EVENT_ACCEPT: {
      xtcpd_init_state(s,
                       XTCP_PROTOCOL_TCP,
                       (unsigned char *) &pcb->remote_ip,
                       pcb->local_port,
                       pcb->remote_port,
                       pcb);
      xtcpd_event(XTCP_NEW_CONNECTION, s);
      break;
    }
    case LWIP_EVENT_CONNECTED: {
      xtcpd_init_state(s,
                       XTCP_PROTOCOL_TCP,
                       (unsigned char *) &pcb->remote_ip,
                       pcb->local_port,
                       pcb->remote_port,
                       pcb);
      xtcpd_event(XTCP_NEW_CONNECTION, s);
      break;
    }
    case LWIP_EVENT_RECV: {
      if (p != NULL) {
        debug_printf("LWIP_EVENT_RECV: %d\n", p->tot_len);
        xscope_int(LWIP_EVENT_RECV_START, p->tot_len);
        if (s->linknum != -1) {

          if (xtcpd_service_client_if_ready(s->linknum, xtcp_links, xtcp_num)) {
            xtcpd_recv_lwip_pbuf(xtcp_links, s->linknum, xtcp_num, s, p);
            tcp_recved(pcb, p->tot_len);
            pbuf_free(p);
          }
          else {
            return ERR_MEM;
          }
        }
        xscope_int(LWIP_EVENT_RECV_STOP, p->tot_len);
      } else if (err == ERR_OK) {
        if (s->s.closed == 0) {
          xtcpd_event(XTCP_CLOSED, s);
          s->s.close_request = 0;
          s->s.closed = 1;
          tcp_close(pcb);
        }
      }
      break;
    }
    case LWIP_EVENT_POLL: {
      if (s->s.close_request) {
        if (!s->s.closed){
          s->s.closed = 1;
          xtcpd_event(XTCP_CLOSED, s);
        }
        debug_printf("CLOSING... %d\n", s->conn.id);
        s->s.close_request = 0;
        tcp_close(pcb);
      }
      break;
    }
    case LWIP_EVENT_SENT: {
      int len;
      xscope_int(TCP_SEND_BUF, tcp_sndbuf(pcb));
      if (s->linknum != -1 && (tcp_sndbuf(pcb) >= tcp_mss(pcb))) {
        len = do_xtcpd_send(xtcp_links[s->linknum],
                            XTCP_SENT_DATA,
                            s,
                            tcp_mss(pcb));
        if (len) {
        err_t r = tcp_write(pcb, (void *)xtcp_links[s->linknum], len, TCP_WRITE_FLAG_XCORE_CHAN_COPY);
        if (r != ERR_OK) fail("tcp_write() failed");
        tcp_output(pcb);
        }
      }
      break;
    }
  }
  return ERR_OK;
}

static int uip_ifstate = 0;


void xtcpd_get_ipconfig(xtcp_ipconfig_t *ipconfig)
{
  IPADDR2_COPY(ipconfig->ipaddr, &netif_default->ip_addr.addr);
  IPADDR2_COPY(ipconfig->netmask, &netif_default->netmask.addr);
  IPADDR2_COPY(ipconfig->gateway, &netif_default->gw.addr);
}

void uip_xtcpd_send_config(int linknum)
{
  if (uip_ifstate) {
    xtcpd_queue_event(xtcp_links[linknum], linknum, XTCP_IFUP);
  }
  else {
    xtcpd_queue_event(xtcp_links[linknum], linknum, XTCP_IFDOWN);
  }
}


void uip_xtcp_checkstate()
{
  int i;

  for (i=0;i<xtcp_num;i++) {
    if (uip_ifstate != prev_ifstate[i]) {
      uip_xtcpd_send_config(i);
      prev_ifstate[i] = uip_ifstate;
    }
  }

}


void lwip_xtcp_up() {
  uip_ifstate = 1;
}

void lwip_xtcp_down() {
  uip_ifstate = 0;
}


int get_uip_xtcp_ifstate()
{
  return uip_ifstate;
}


void xtcpd_set_poll_interval(int linknum, int conn_id, int poll_interval)
{
  xtcpd_state_t *s = xtcpd_lookup_tcp_state(conn_id);
  if (s != NULL && s->conn.protocol == XTCP_PROTOCOL_UDP) {
    s->s.poll_interval = poll_interval;
    uip_timer_set(&(s->s.tmr), poll_interval * CLOCK_SECOND/1000);
  }
}

void xtcpd_join_group(xtcp_ipaddr_t addr)
{
#if UIP_IGMP
  uip_ipaddr_t ipaddr;
  uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
  igmp_join_group(ipaddr);
#endif
}

void xtcpd_leave_group(xtcp_ipaddr_t addr)
{
#if UIP_IGMP
  uip_ipaddr_t ipaddr;
  uip_ipaddr(ipaddr, addr[0], addr[1], addr[2], addr[3]);
  igmp_leave_group(ipaddr);
#endif
}

void xtcpd_get_mac_address(unsigned char mac_addr[]){
/*
  mac_addr[0] = uip_ethaddr.addr[0];
  mac_addr[1] = uip_ethaddr.addr[1];
  mac_addr[2] = uip_ethaddr.addr[2];
  mac_addr[3] = uip_ethaddr.addr[3];
  mac_addr[4] = uip_ethaddr.addr[4];
  mac_addr[5] = uip_ethaddr.addr[5];
*/
}
