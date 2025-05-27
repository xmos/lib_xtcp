// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef __xtcp_lwip_includes_h__
#define __xtcp_lwip_includes_h__

/* Work around xC keywords used as variable names in lwIP */
#define in _in
#define module _module
#define forward _forward
#define interface _interface
#define port _port
#define timer _timer
#ifdef __XC__
extern "C" {
#endif

#define USE_LWIP

/* The include files */
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "netif/etharp.h"
#include "lwip/autoip.h"
#include "lwip/init.h"
#include "lwip/tcp.h"
#include "lwip/tcp_impl.h"
#include "lwip/igmp.h"
#include "lwip/dhcp.h"
#include "lwip/dns.h"

#ifdef __XC__
}
#endif
#undef in
#undef module
#undef forward
#undef interface
#undef port
#undef timer

#endif /* __xtcp_lwip_includes_h__ */
