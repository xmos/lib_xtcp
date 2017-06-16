// Copyright (c) 2016, XMOS Ltd, All rights reserved
#ifndef __xtcp_uip_includes_h__
#define __xtcp_uip_includes_h__

/* Work around xC keywords used as variable names in uIP */
#define in _in
#define module _module
#define forward _forward
#define interface _interface
#define port _port
#define timer _timer
#ifdef __XC__
extern "C" {
#endif

#define USE_UIP

/* The include files */
#include "xtcp_uip/uip.h"
#include "xtcp_uip/autoip/autoip.h"
#include "xtcp_uip/igmp/igmp.h"
#include "xtcp_uip/dhcpc/dhcpc.h"
#include "xtcp_uip/uip_arp.h"
#include "xtcp_uip/uip-split.h"

#ifdef __XC__
}
#endif
#undef in
#undef module
#undef forward
#undef interface
#undef port
#undef timer

#endif /* __xtcp_uip_includes_h__ */
