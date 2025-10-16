// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "lwip_shim.h"

#include <stdint.h>
#include <string.h>

/* XTCP headers */
#include "client_queue.h"
#include "connection.h"
#include "debug_print.h"
#include "dns_found.h"
#include "udp_recv.h"

/* LwIP headers */
#include "lwip/dns.h"
#include "lwip/ip.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/igmp.h"

xtcp_error_int32_t shim_new_socket(unsigned client_num, xtcp_protocol_t protocol) {
  xtcp_error_int32_t connection = assign_client_connection(client_num, protocol);
  if (connection.status != XTCP_SUCCESS) {
    debug_printf("No free client connection available\n");
    return connection;
  }

  if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = udp_new_ip_type(IPADDR_TYPE_ANY);
    if (udp_pcb == NULL) {
      connection.status = XTCP_ENOMEM;
      connection.value = -1;
    } else if (set_udp_pcb(connection.value, udp_pcb) < 0) {
      udp_remove(udp_pcb);
      connection.status = XTCP_EINVAL;
      connection.value = -1;
    }

  } else if (protocol == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb* tcp_pcb = tcp_new_ip_type(IPADDR_TYPE_ANY);
    if (tcp_pcb == NULL) {
      connection.status = XTCP_ENOMEM;
      connection.value = -1;
    } else if (set_tcp_pcb(connection.value, tcp_pcb) < 0) {
      tcp_close(tcp_pcb);
      connection.status = XTCP_EINVAL;
      connection.value = -1;
    }
  }

  return connection;
}

void shim_close_socket(unsigned client_num, int32_t id) {
  xtcp_error_int32_t connection = find_client_connection(client_num, id);
  if (connection.status != XTCP_SUCCESS) {
    debug_printf("No active client connection found\n");
    return;
  }

  free_notifications_on_queue(client_num, id);
  clear_pending_rx_data_on_connection(id);

  xtcp_protocol_t protocol = get_protocol(id);
  if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = get_udp_pcb(id);
    if (udp_pcb == NULL) {
      debug_printf("Failed to get UDP PCB\n");

    } else {
      udp_remove(udp_pcb);
    }

  } else if (protocol == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb* tcp_pcb = get_tcp_pcb(id);
    if (tcp_pcb == NULL) {
      debug_printf("Failed to get TCP PCB\n");

    } else {
      tcp_close(tcp_pcb);
    }
  }
  free_client_connection(id);
}

xtcp_error_code_t shim_listen(unsigned client_num, int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr) {
  xtcp_error_code_t result = XTCP_EINVAL;
  xtcp_error_int32_t connection = find_client_connection(client_num, id);
  if (connection.status != XTCP_SUCCESS) {
    // Bad parameter or inactive connection
    return connection.status;
  }

  ip_addr_t bind_addr;
  memcpy(&bind_addr, ipaddr, sizeof(ip_addr_t));

  xtcp_protocol_t protocol = get_protocol(id);
  if (protocol == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb* tcp_pcb = get_tcp_pcb(id);
    if (tcp_pcb != NULL) {
      err_t err = tcp_bind(tcp_pcb, &bind_addr, port_number);
      if (err == ERR_OK) {
        /* Listen will cycle pcb giving us a listen pcb */
        struct tcp_pcb* listen_pcb = tcp_listen(tcp_pcb);
        if (listen_pcb != NULL) {
          result = XTCP_SUCCESS;
          set_tcp_pcb(id, listen_pcb);
          tcp_arg(listen_pcb, (void*)id);
        }
      } else if (err == ERR_USE) {
        result = XTCP_EINUSE;
      } else {
        debug_printf("listen: Failed to bind to port %d, err %d\n", port_number, err);
      }
    }

  } else if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = get_udp_pcb(id);
    if (udp_pcb != NULL) {
      err_t err = udp_bind(udp_pcb, &bind_addr, port_number);
      if (err == ERR_OK) {
        result = XTCP_SUCCESS;
        udp_recv(udp_pcb, xtcp_udp_recv, (void*)id);  // Should be index but they are currently the same.
      }
    }
  }

  return result;
}

xtcp_error_int32_t shim_accept(unsigned client_num, struct tcp_pcb* new_pcb, int32_t old_id) {
  xtcp_protocol_t protocol = get_protocol(old_id);
  xtcp_error_int32_t connection = {XTCP_EINVAL, -1};

  if (protocol == XTCP_PROTOCOL_UDP) {
    connection.status = XTCP_EPROTONOSUPPORT;
    connection.value = -1;

  } else if (protocol == XTCP_PROTOCOL_TCP) {
    if (new_pcb != NULL) {
      // Accepting connection provides us with a new PCB, so assign new connection id
      connection = assign_client_connection(client_num, protocol);
      if (connection.status != XTCP_SUCCESS) {
        return connection;
      }
      int32_t new_index = connection.value;

      set_tcp_pcb(new_index, new_pcb);
      tcp_arg(new_pcb, (void*)new_index);
    }
  }

  return connection;
}

xtcp_error_code_t shim_connect(unsigned client_num, int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr) {
  xtcp_error_code_t result = XTCP_EINVAL;
  xtcp_error_int32_t connection = find_client_connection(client_num, id);
  if (connection.status != XTCP_SUCCESS) {
    // Bad parameter or inactive connection
    return connection.status;
  }
  ip_addr_t remote_addr;
  memcpy(&remote_addr, ipaddr, sizeof(ip_addr_t));

  xtcp_protocol_t protocol = get_protocol(id);
  if (protocol == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb* tcp_pcb = get_tcp_pcb(id);
    if (tcp_pcb != NULL) {
      err_t err = tcp_connect(tcp_pcb, &remote_addr, port_number, NULL);
      if (err == ERR_OK) {
        result = XTCP_SUCCESS;
      }
    }

  } else if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = get_udp_pcb(id);
    if (udp_pcb != NULL) {
      // ip_set_option(udp_pcb, SOF_BROADCAST);  // Allow broadcast sends
      err_t err = udp_connect(udp_pcb, &remote_addr, port_number);
      if (err == ERR_OK) {
        udp_recv(udp_pcb, xtcp_udp_recv, (void*)id);
        result = XTCP_SUCCESS;
      }
    }
  }

  return result;
}

xtcp_error_code_t shim_send(unsigned client_num, int32_t id, void* buffer_token) {
  xtcp_error_code_t result = XTCP_EINVAL;
  if (buffer_token == NULL) {
    return XTCP_EINVAL;
  }
  xtcp_error_int32_t connection = find_client_connection(client_num, id);
  if (connection.status != XTCP_SUCCESS) {
    // Bad parameter or inactive connection
    return connection.status;
  }

  struct pbuf* new_pbuf = buffer_token;
  
  xtcp_protocol_t protocol = get_protocol(id);
  if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = get_udp_pcb(id);
    if (udp_pcb != NULL) {
      err_t error = udp_send(udp_pcb, new_pbuf);
      if (error == ERR_OK) {
        result = XTCP_SUCCESS;
      }
    }
    pbuf_free(new_pbuf);

  } else if (protocol == XTCP_PROTOCOL_TCP) {
    struct tcp_pcb* tcp_pcb = get_tcp_pcb(id);
    if (tcp_pcb != NULL) {
      // TODO - move tcp write to new function, using memory pools of other buffer
      err_t error = tcp_write(tcp_pcb, new_pbuf->payload, new_pbuf->len, TCP_WRITE_FLAG_COPY);
      if (error == ERR_OK) {
        err_t output = tcp_output(tcp_pcb);  // Ensure data is sent immediately
        if (output == ERR_OK) {
          result = XTCP_SUCCESS;
        }
      }
    }
    pbuf_free(new_pbuf);
  }
  return result;
}

xtcp_error_code_t shim_sendto(unsigned client_num, int32_t id, void* buffer_token, xtcp_ipaddr_t remote_addr, uint16_t remote_port) {
  xtcp_error_code_t result = XTCP_EINVAL;
  if (buffer_token == NULL) {
    return XTCP_EINVAL;
  }
  xtcp_error_int32_t connection = find_client_connection(client_num, id);
  if (connection.status != XTCP_SUCCESS) {
    // Bad parameter or inactive connection
    return connection.status;
  }
  struct pbuf* new_pbuf = buffer_token;

  xtcp_protocol_t protocol = get_protocol(id);
  if (protocol == XTCP_PROTOCOL_UDP) {
    struct udp_pcb* udp_pcb = get_udp_pcb(id);
    if (udp_pcb != NULL) {
      ip_addr_t addr;
      memcpy(&addr, remote_addr, sizeof(ip_addr_t));
      err_t error = udp_sendto(udp_pcb, new_pbuf, &addr, remote_port);
      if (error == ERR_OK) {
        result = XTCP_SUCCESS;
      }
    }
    pbuf_free(new_pbuf);
  } else if (protocol == XTCP_PROTOCOL_TCP) {
    // TCP does not support sendto
    result = XTCP_EPROTONOSUPPORT;
  }

  return result;
}

xtcp_error_code_t shim_join_multicast_group(xtcp_ipaddr_t addr) {
  xtcp_error_code_t result = XTCP_EINVAL;
  ip_addr_t group_addr;
  memcpy(&group_addr, addr, sizeof(ip_addr_t));

  ip_addr_t netif_addr;
  ip4_addr_set_any(&netif_addr);
  // TODO - selecting netif, for handling multiple interfaces
  err_t err = igmp_joingroup(&netif_addr, &group_addr);
  if (err == ERR_OK) {
    result = XTCP_SUCCESS;
  }
  return result;
}

xtcp_error_code_t shim_leave_multicast_group(xtcp_ipaddr_t addr) {
  xtcp_error_code_t result = XTCP_EINVAL;
  ip_addr_t group_addr;
  memcpy(&group_addr, addr, sizeof(ip_addr_t));

  ip_addr_t netif_addr;
  ip4_addr_set_any(&netif_addr);
  // TODO - selecting netif, for handling multiple interfaces
  err_t err = igmp_leavegroup(&netif_addr, &group_addr);
  if (err == ERR_OK) {
    result = XTCP_SUCCESS;
  }
  return result;
}

xtcp_host_t shim_request_host_by_name(unsigned client_num, const uint8_t hostname[], xtcp_ipaddr_t dns_server) {
  xtcp_host_t result = { .ipaddr = {0}, .port_number = 0 };

  ip_addr_t ipaddr = IPADDR4_INIT_BYTES(0,0,0,0);
  ip_addr_t server;
  memcpy(&server, dns_server, sizeof(xtcp_ipaddr_t));
  dns_setserver(0, &server);

  err_t dns_result = dns_gethostbyname((const char *)hostname, &ipaddr, xtcp_dns_found, (void *)client_num);
  if (dns_result == ERR_OK) {
    memcpy(result.ipaddr, &ipaddr, sizeof(ip_addr_t));
  } else if (dns_result == ERR_INPROGRESS) {
    // DNS request is in progress, result will be available when XTCP_DNS_RESULT event is received
  } else {
    debug_printf("shim_request_host_by_name: DNS request failed for %s, err %d\n", hostname, dns_result);
  }
  return result;
}
