// Copyright (c) 2016-2017, XMOS Ltd, All rights reserved
#ifndef __xtcp_shared_includes_h__
#define __xtcp_shared_includes_h__

#include "xtcp.h"

typedef struct client_queue_t {
  xtcp_event_type_t xtcp_event;
  /* Pointer to connection in uIP or LWIP */
  xtcp_connection_t *unsafe xtcp_conn;
  struct pbuf *unsafe pbuf;
} client_queue_t;

inline void printip(xtcp_ipaddr_t ipaddr);

unsigned get_if_state(void);
void renotify(unsigned client_num);
void xtcp_init_queue(static const unsigned n_xtcp, server xtcp_if i_xtcp_init[n_xtcp]);
xtcp_connection_t create_xtcp_state(int xtcp_num, xtcp_protocol_t protocol,
                                           unsigned char * unsafe remote_addr,
                                           int local_port, int remote_port,
                                           void * unsafe uip_lwip_conn);

client_queue_t dequeue_event(unsigned client_num);
void enqueue_event_and_notify(unsigned client_num,
                                     xtcp_event_type_t xtcp_event,
                                     xtcp_connection_t * unsafe xtcp_conn,
                                     struct pbuf *unsafe pbuf
                                     );

void rm_recv_events(unsigned conn_id, unsigned client_num);

void xtcp_if_up(void);
void xtcp_if_down(void);

#endif /* __xtcp_shared_includes_h__ */
