// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XTCP_PBUF_SHIM_H
#define XTCP_PBUF_SHIM_H

#include "xtcp.h"

void* unsafe pbuf_shim_alloc_tx(uint16_t length);

void* unsafe pbuf_shim_token_payload(void* unsafe buffer_token);

#endif /* XTCP_PBUF_SHIM_H */
