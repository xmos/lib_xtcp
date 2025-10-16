// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XTCP_PBUF_SHIM_H
#define XTCP_PBUF_SHIM_H

#include <stdint.h>

#include "xc2compat.h"
#include "xtcp.h"

/* allocate a lwip 'struct pbuf' from XC code. Returns pointer to pbuf as a void*, or buffer token. */
void* unsafe pbuf_shim_alloc_tx(uint16_t length);

/* Converts a buffer token (void*) to a pointer to the pbuf payload. */
void* unsafe pbuf_shim_token_payload(void* unsafe buffer_token);

/* TODO - add pbuf_shim_free_tx(), pbuf is currently freed in shim_send() */

#endif /* XTCP_PBUF_SHIM_H */
