// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef __UDP_REFLECT_H__
#define __UDP_REFLECT_H__

#include "xtcp.h"

/** \brief Simple UDP packet reflection example.
 * 
 * This returns packets to the source IP address, but changes the case to upper
 * to show that the packet has been seen and turned around.
 * 
 * \param i_xtcp    TCP configuration interface served by xtcp_uip() or xtcp_lwip() 
 */
void udp_reflect(client xtcp_if i_xtcp);

#endif /* __UDP_REFLECT_H__ */
