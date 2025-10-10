// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#define DEBUG_UNIT LIB_XTCP

#include "dns_found.h"

#include <stdint.h>
#include <string.h>

/* XMOS library headers */
#include "client_queue.h"
#include "connection.h"
#include "debug_print.h"
#include "xtcp.h"

/* LwIP headers */
#include "lwip/dns.h"
#include "lwip/ip.h"

__attribute__((fptrgroup("dns_found_callback")))
void xtcp_dns_found(const char *name, const ip_addr_t *ipaddr, void *callback_arg) {
  unsigned client_num = (unsigned)callback_arg;
  xtcp_error_code_t result = XTCP_EINVAL;

  if ((client_num < MAX_XTCP_CLIENTS) && (name != NULL)) {
    if (ipaddr != NULL) {
      result = XTCP_SUCCESS;

    } else {
      debug_printf("xtcp_dns_found: DNS lookup failed for \"%s\"\n", name);
      result = XTCP_ENOMEM;

    }
  } else {
    debug_printf("xtcp_dns_found: Invalid parameters: index=%d, name=%p, ipaddr=%p\n", index, name, ipaddr);
  }

  xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, result, XTCP_DNS_RESULT);
  if (enqueue != XTCP_SUCCESS) {
    debug_printf("xtcp_dns_found: enqueue_event_and_notify failed: %d\n", enqueue);
  }
}
