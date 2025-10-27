// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "xtcp.h"

#include <string.h>

#include "debug_print.h"
#include "ethernet.h"

__attribute__((weak)) void xtcp_configure_mac(unsigned netif_id, uint8_t mac_address[MACADDR_NUM_BYTES]) {
  (void)netif_id;
  memset(mac_address, 0, MACADDR_NUM_BYTES);
  debug_printf("xtcp_configure_mac: Override this function to set a valid MAC address, returning zero MAC address\n");
}
