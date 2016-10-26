#include "xc2compat.h"
#include <string.h>
#include <xassert.h>
#include <print.h>
#include <debug_print.h>
#include "xtcp.h"
#include "xtcp_shared.h"
#if (XTCP_STACK == LWIP)
#include "xtcp_lwip_includes.h"
#endif

/* A 2D array of queue items */
static client_queue_t client_queue[MAX_XTCP_CLIENTS][CLIENT_QUEUE_SIZE] = {{{0}}};
static unsigned client_heads[MAX_XTCP_CLIENTS] = {0};
static unsigned client_num_events[MAX_XTCP_CLIENTS] = {0};
static server xtcp_if * unsafe i_xtcp; /* Used for notifying */
static unsigned ifstate = 0;           /* Connection state */
static unsigned n_xtcp;

#if (XTCP_STACK == LWIP)
unsafe client_queue_t
new_event(xtcp_event_type_t xtcp_event,
          xtcp_connection_t conn,
          struct tcp_pcb * unsafe t_pcb,
          struct udp_pcb * unsafe u_pcb,
          struct pbuf *unsafe pbuf)
{
  client_queue_t event;
  event.xtcp_event = xtcp_event;
  event.conn = conn;
  event.t_pcb = t_pcb;
  event.u_pcb = u_pcb;
  event.pbuf = pbuf;
  return event;
}

#else /* UIP */
unsafe client_queue_t
new_event(xtcp_event_type_t xtcp_event,
          xtcp_connection_t conn)
{
  client_queue_t event;
  event.xtcp_event = xtcp_event;
  event.conn = conn;
  return event;
}
#endif

unsafe void
xtcp_init_queue(static const unsigned n_xtcp_init, server xtcp_if i_xtcp_init[n_xtcp_init])
{
  xassert(n_xtcp <= MAX_XTCP_CLIENTS);
  i_xtcp = i_xtcp_init;
  memset(client_queue, 0, sizeof(client_queue));
  memset(client_heads, 0, sizeof(client_heads));
  memset(client_num_events, 0, sizeof(client_num_events));
  n_xtcp = n_xtcp_init;
}

unsafe void 
renotify(unsigned client_num)
{
  if(client_num_events[client_num] > 0) {
    i_xtcp[client_num].packet_ready();
  }
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

unsafe xtcp_connection_t
create_xtcp_state(int xtcp_num,
                  xtcp_protocol_t protocol,
                  unsigned char * unsafe remote_addr,
                  int local_port,
                  int remote_port,
                  void * unsafe uip_lwip_conn)
{
  xtcp_connection_t xtcp_conn = {0};

  xtcp_conn.client_num = xtcp_num;
  xtcp_conn.id = get_guid();
  xtcp_conn.protocol = protocol;
  for (int i=0; i<4; i++)
    xtcp_conn.remote_addr[i] = remote_addr[i];
  xtcp_conn.remote_port = remote_port;
  xtcp_conn.local_port = local_port;

  xtcp_conn.stack_conn = (int) uip_lwip_conn;
  return xtcp_conn;
}

unsafe client_queue_t 
dequeue_event(unsigned client_num)
{
  client_num_events[client_num]--;
  xassert(client_num_events[client_num] >= 0);

  unsigned position = client_heads[client_num];
  client_heads[client_num] = (client_heads[client_num] + 1) % CLIENT_QUEUE_SIZE;
  return client_queue[client_num][position];
}

unsafe void
enqueue_event_and_notify(unsigned client_num, client_queue_t event)
{
  unsigned position = (client_heads[client_num] + client_num_events[client_num]) % CLIENT_QUEUE_SIZE;
  client_queue[client_num][position] = event;

  client_num_events[client_num]++;
  xassert(client_num_events[client_num] <= CLIENT_QUEUE_SIZE);

  /* Notify */
  i_xtcp[client_num].packet_ready();
}

unsafe client_queue_t 
rm_next_recv_event(xtcp_connection_t xtcp_conn, unsigned client_num)
{
  client_queue_t offending_item = {0};
  for(int i=0; i<client_num_events[client_num]; i++) {
    unsigned place_in_queue = (client_heads[client_num] + i) % CLIENT_QUEUE_SIZE;
    client_queue_t current_queue_item = client_queue[client_num][place_in_queue];
    
    if(current_queue_item.xtcp_event == XTCP_RECV_DATA &&
       current_queue_item.conn.id == xtcp_conn.id) {
      offending_item = current_queue_item;
      
      for(int j=i; j<client_num_events[client_num] - 1; j++) {
        unsigned place = (client_heads[client_num] + j) % CLIENT_QUEUE_SIZE;
        unsigned next_place = ++place % CLIENT_QUEUE_SIZE;
        client_queue[client_num][place] = client_queue[client_num][next_place];
      }

      client_num_events[client_num]--;
      break;
    }
  }
  return offending_item;
}

unsigned 
get_if_state(void) 
{ 
  return ifstate;
}

unsafe void
xtcp_if_up(void)
{
  ifstate = 1;
  xtcp_connection_t dummy = {0};
  for(unsigned i=0; i<n_xtcp; i++) {
#if (XTCP_STACK == LWIP)
    enqueue_event_and_notify(i, new_event(XTCP_IFUP, dummy, NULL, NULL, NULL));
#else /* uIP */
    enqueue_event_and_notify(i, new_event(XTCP_IFUP, dummy));
#endif
  }
}

unsafe void
xtcp_if_down(void)
{
  ifstate = 0;
  xtcp_connection_t dummy = {0};
  for(unsigned i=0; i<n_xtcp; i++) {
#if (XTCP_STACK == LWIP)
    enqueue_event_and_notify(i, new_event(XTCP_IFDOWN, dummy, NULL, NULL, NULL));
#else /* uIP */
    enqueue_event_and_notify(i, new_event(XTCP_IFDOWN, dummy));
#endif
  }
}