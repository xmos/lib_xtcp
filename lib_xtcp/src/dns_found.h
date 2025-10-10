// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef DNS_FOUND_H
#define DNS_FOUND_H

#include "lwip/dns.h"

void xtcp_dns_found(const char *name, const ip_addr_t *ipaddr, void *callback_arg);

#endif /* DNS_FOUND_H */
