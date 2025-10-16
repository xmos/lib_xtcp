// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "pbuf_shim.h"

#include <stdint.h>
#include <string.h>

/* XTCP headers */
#include "debug_print.h"

/* LwIP headers */
#include "lwip/pbuf.h"


void* pbuf_shim_alloc_tx(uint16_t length) {
  struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, length, PBUF_RAM);
  if (p == NULL) {
    debug_printf("Failed to allocate pbuf of type %d and length %d/%d\n", PBUF_TRANSPORT, length, p->tot_len);
  }
  return p;
}

void* unsafe pbuf_shim_token_payload(void* unsafe buffer_token) {
  struct pbuf* p = buffer_token;
  if (p == NULL) {
    debug_printf("Bad parameter, pbuf token\n");
    return NULL;
  }
  return p->payload;
}
