// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include "uip_timer.h"
#include "xtcp.h"

typedef struct xtcp_server_state_t {
  int send_request;
  int abort_request;
  int close_request;
  int poll_interval;
  int connect_request;
  int ack_request;
  int closed;
  struct uip_timer tmr;
  int uip_conn;
  int ack_recv_mode;
#ifdef XTCP_ENABLE_PARTIAL_PACKET_ACK
  int accepts_partial_ack;
#endif
} xtcp_server_state_t;
