// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "xassert.h"
#include "xtcp.h"
#include "client_queue.h"

static server xtcp_if* unsafe i_xtcp; /* Used for notifying */
static unsigned n_xtcp = 0;           /* Number of clients */

void client_init_notification(static const unsigned n_xtcp_init, server xtcp_if i_xtcp_init[n_xtcp_init]) {
  xassert(n_xtcp <= MAX_XTCP_CLIENTS);
  unsafe { i_xtcp = i_xtcp_init; }
  n_xtcp = n_xtcp_init;
}

void client_intf_notify(unsigned client_num) {
  /* Notify */
  if (n_xtcp != 0) {
    unsafe { i_xtcp[client_num].event_ready(); }
  }
}
