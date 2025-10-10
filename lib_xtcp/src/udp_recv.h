// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef UDP_RECV_H
#define UDP_RECV_H

#include "lwip/udp.h"
#include "xtcp.h"

void xtcp_udp_recv(void* arg, struct udp_pcb* upcb,  struct pbuf* p, const ip_addr_t* addr, u16_t port);

#endif /* UDP_RECV_H */
