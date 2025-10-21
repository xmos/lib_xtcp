// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XTCP_CONNECTION_H
#define XTCP_CONNECTION_H

#include <stdint.h>

#include "xtcp.h"

#define MAX_OPEN_SOCKETS (MEMP_NUM_UDP_PCB + MEMP_NUM_TCP_PCB)

void init_client_connections(void);
xtcp_error_int32_t find_client_connection(unsigned client_num, int32_t id);

xtcp_error_int32_t assign_client_connection(unsigned client_num, xtcp_protocol_t protocol);

void clear_pending_rx_data_on_connection(int32_t index);
void free_client_connection(int32_t index);


xtcp_error_int32_t is_active(int32_t index);

xtcp_host_t get_remote_from_pcb(int32_t index);
xtcp_host_t get_local_from_pcb(int32_t index);
xtcp_host_t get_remote(int32_t index);
unsigned get_client_info(int32_t index);

xtcp_error_int32_t get_remote_data(int32_t index, uint8_t * unsafe * unsafe data, int32_t length, uint32_t *unsafe timestamp);
int32_t free_remote_data(int32_t index);

xtcp_protocol_t get_protocol(int32_t index);

int32_t set_connection_client_data(int32_t index, void * unsafe data);
void * unsafe get_connection_client_data(int32_t index);

#ifndef __XC__

/* LWIP headers */
#include "lwip/tcp.h"
#include "lwip/udp.h"

xtcp_error_code_t set_udp_pcb(int32_t index, struct udp_pcb *udp_pcb);
xtcp_error_code_t set_tcp_pcb(int32_t index, struct tcp_pcb *tcp_pcb);

struct udp_pcb *get_udp_pcb(int32_t index);
struct tcp_pcb *get_tcp_pcb(int32_t index);

xtcp_error_code_t set_remote(int32_t index, const ip_addr_t *remote, uint16_t port_number, struct pbuf *pbuf);
xtcp_error_code_t unlink_remote(int32_t index, struct pbuf *pbuf);

#endif /* __XC__ */

#endif /* XTCP_CONNECTION_H */
