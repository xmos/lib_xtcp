// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XTCP_LWIP_SHIM_H
#define XTCP_LWIP_SHIM_H

#include "xtcp.h"

xtcp_error_int32_t shim_new_socket(unsigned client_num, xtcp_protocol_t protocol);
void shim_close_socket(unsigned client_num, int32_t index);

xtcp_error_code_t shim_listen(unsigned client_num, int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr);
#ifndef __XC__
#include "lwip/tcp.h"
xtcp_error_int32_t shim_accept(unsigned client_num, struct tcp_pcb* new_pcb, int32_t old_id);
#endif
xtcp_error_code_t shim_connect(unsigned client_num, int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr);

xtcp_error_code_t shim_send(unsigned client_num, int32_t id, void* unsafe buffer_token);
xtcp_error_code_t shim_sendto(unsigned client_num, int32_t id, void* unsafe buffer_token, xtcp_ipaddr_t remote_addr, uint16_t remote_port);

xtcp_error_code_t shim_join_multicast_group(xtcp_ipaddr_t addr);
xtcp_error_code_t shim_leave_multicast_group(xtcp_ipaddr_t addr);

xtcp_remote_t shim_request_host_by_name(unsigned client_num, const uint8_t hostname[], xtcp_ipaddr_t dns_server);

#endif /* XTCP_LWIP_SHIM_H */
