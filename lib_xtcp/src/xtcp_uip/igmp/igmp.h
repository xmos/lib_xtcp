// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef _igmp_h_
#define _igmp_h_

void igmp_init();

void igmp_periodic();
void igmp_in();
void igmp_join_group(uip_ipaddr_t addr);
void igmp_leave_group(uip_ipaddr_t addr);
int igmp_check_addr(uip_ipaddr_t addr);
#endif // _igmp_h_
