// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef _autoip_h_
#define _autoip_h_

void uip_autoip_init(int seed);
void uip_autoip_arp_in();
void uip_autoip_start();
void uip_autoip_stop();
void uip_autoip_configured(uip_ipaddr_t ipaddr);
void uip_autoip_periodic();

#endif //_autoip_h_
