// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#define DEBUG_UNIT LIB_XTCP

#include "udp_recv.h"

/* XMOS library headers */
#include "client_queue.h"
#include "connection.h"
#include "debug_print.h"

/* LwIP headers */
#include "lwip/ip.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"

__attribute__((fptrgroup("udp_pcb_recv"))) 
void xtcp_udp_recv(void* arg, struct udp_pcb* upcb,  struct pbuf* p, const ip_addr_t* addr, u16_t port) {
  int32_t index = (int32_t)arg;  // arg is the index in the connection array

  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (p != NULL)) {
    set_remote(index, addr, port, p);

    xtcp_event_type_t event;
    if (upcb->flags & UDP_FLAGS_CONNECTED) {
      event = XTCP_RECV_DATA;
    } else {
      event = XTCP_RECV_FROM_DATA;
    }
    xtcp_error_code_t result = enqueue_event_and_notify(get_client_info(index), index, event);
    if (result != XTCP_SUCCESS) {
      debug_printf("xtcp_udp_recv: enqueue_event_and_notify failed: %d\n", result);
      // Free the pbuf since we couldn't enqueue the event
      pbuf_free(p);
    }
  } else {
    debug_printf("Received bad index or NULL pbuf, skipping\n");
  }
}
