// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "connection.h"

#include <stdint.h>

#include "xtcp.h"

/* Lwip headers */
#include "lwip/pbuf.h"

typedef enum connection_state_e {
  XTCP_NULL_STATE = 0,
  XTCP_CONNECT_PENDING = 1,
  XTCP_CONNECTED = 2,
  XTCP_LISTENING = 4
} connection_state_t;

typedef struct connection_entry_s {
  int32_t is_active;
  unsigned client_num;
  connection_state_t state;
  xtcp_protocol_t protocol;
  union pcb {
    struct tcp_pcb *tcp;
    struct udp_pcb *udp;
  } pcb;
  struct pbuf *pbuf;          // UDP/TCP, Pointer to pbuf data received.
  void * unsafe client_data;  // Pointer to additional client data
} connection_entry_t;

#define DEINIT UINT32_MAX

static connection_entry_t connections[MAX_OPEN_SOCKETS];

void init_client_connections(void) {
  for (int32_t i = 0; i < MAX_OPEN_SOCKETS; ++i) {
    connections[i].is_active = 0;
    connections[i].client_num = DEINIT;
    connections[i].state = XTCP_NULL_STATE;
    connections[i].protocol = XTCP_PROTOCOL_NONE;
    connections[i].pcb.tcp = NULL;
    connections[i].pbuf = NULL;
    connections[i].client_data = NULL;
  }
}

xtcp_error_int32_t find_client_connection(unsigned client_num, int32_t id) {
  xtcp_error_int32_t result = {.status = XTCP_EINVAL, .value = -1};
  for (int32_t i = 0; i < MAX_OPEN_SOCKETS; ++i) {
    if (connections[i].client_num == client_num && (i == id)) {
      result.status = XTCP_SUCCESS;
      result.value = i;
      return result;
    }
  }

  return result;
}

void clear_pending_rx_data_on_connection(int32_t index) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    if (connections[index].pbuf != NULL) {
      if (connections[index].protocol == XTCP_PROTOCOL_TCP) {
        uint16_t length = connections[index].pbuf->tot_len;
        tcp_recved(connections[index].pcb.tcp, length);
      }
      pbuf_free(connections[index].pbuf);
      connections[index].pbuf = NULL;
    }
  }
}

void free_client_connection(int32_t index) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    connections[index].is_active = 0;
    connections[index].client_num = DEINIT;
    connections[index].state = XTCP_NULL_STATE;
    connections[index].protocol = XTCP_PROTOCOL_NONE;
    connections[index].pcb.tcp = NULL;
    connections[index].client_data = NULL;
  }
}

xtcp_error_int32_t assign_client_connection(unsigned client_num, xtcp_protocol_t protocol) {
  static int32_t last_guid = 0;
  xtcp_error_int32_t result = {.status = XTCP_ENOMEM, .value = -1};
  // Find a free connection
  for (int32_t i = 0; i < MAX_OPEN_SOCKETS; ++i) {
    int32_t index = last_guid + i;
    if (index >= MAX_OPEN_SOCKETS) {
      index = index - MAX_OPEN_SOCKETS;
    }
    if (connections[index].is_active == 0) {
      last_guid = index + 1;
      result.value = index;
      result.status = XTCP_SUCCESS;
      break;
    }
  }
  if (result.status == XTCP_SUCCESS) {
    int32_t index = result.value;
    connections[index].is_active = 1;
    connections[index].client_num = client_num;
    connections[index].state = XTCP_NULL_STATE;
    connections[index].protocol = protocol;
    connections[index].pcb.tcp = NULL;
  }
  return result;
}

xtcp_error_int32_t is_active(int32_t index) {
  xtcp_error_int32_t result = {.status = XTCP_EINVAL, .value = -1};
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    result.status = XTCP_SUCCESS;
    result.value = connections[index].is_active;
  }
  return result;
}

xtcp_error_code_t set_udp_pcb(int32_t index, struct udp_pcb *udp_pcb) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (connections[index].protocol == XTCP_PROTOCOL_UDP)) {
    connections[index].pcb.udp = udp_pcb;
    return XTCP_SUCCESS;
  }
  return XTCP_EINVAL;
}

xtcp_error_code_t set_tcp_pcb(int32_t index, struct tcp_pcb *tcp_pcb) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (connections[index].protocol == XTCP_PROTOCOL_TCP)) {
    connections[index].pcb.tcp = tcp_pcb;
    return XTCP_SUCCESS;
  }
  return XTCP_EINVAL;
}

xtcp_protocol_t get_protocol(int32_t index) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    return connections[index].protocol;
  }
  return XTCP_PROTOCOL_NONE;  // Error
}

struct udp_pcb *get_udp_pcb(int32_t index) {
  struct udp_pcb *udp_pcb;
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (connections[index].protocol == XTCP_PROTOCOL_UDP)) {
    udp_pcb = connections[index].pcb.udp;
    return udp_pcb;  // Success
  }
  return NULL;  // Error
}

struct tcp_pcb *get_tcp_pcb(int32_t index) {
  struct tcp_pcb *tcp_pcb;
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (connections[index].protocol == XTCP_PROTOCOL_TCP)) {
    tcp_pcb = connections[index].pcb.tcp;
    return tcp_pcb;  // Success
  }
  return NULL;  // Error
}

unsigned get_client_info(int32_t index) {
  unsigned client_num = DEINIT;
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    client_num = connections[index].client_num;
  }
  return client_num;
}

xtcp_error_code_t set_remote(int32_t index, const ip_addr_t *remote, uint16_t port_number, struct pbuf *pbuf) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    if (pbuf != NULL) {
      
      if (remote != NULL) {
        memcpy(pbuf->remote.ipaddr, remote, sizeof(ip_addr_t));
      } else {
        memset(pbuf->remote.ipaddr, 0, sizeof(ip_addr_t));
      }
      pbuf->remote.port_number = port_number;

      if (connections[index].pbuf != NULL) {
        struct pbuf *pbuf_queue;

        // Find last pbuf in queue
        for (pbuf_queue = connections[index].pbuf; pbuf_queue->next != NULL;
            pbuf_queue = pbuf_queue->next);

        pbuf_queue->next = pbuf;
      } else {
        connections[index].pbuf = pbuf;
      }
      return XTCP_SUCCESS;
    }
  }
  return XTCP_EINVAL;
}

xtcp_remote_t get_remote_from_pcb(int32_t index) {
  xtcp_remote_t remote = {.ipaddr = {0}, .port_number = 0};
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    if (connections[index].protocol == XTCP_PROTOCOL_TCP) {
      struct tcp_pcb* tcp_pcb = get_tcp_pcb(index);
      if (tcp_pcb != NULL) {
        memcpy(remote.ipaddr, &tcp_pcb->remote_ip, sizeof(xtcp_ipaddr_t));
        remote.port_number = tcp_pcb->remote_port;
      }
    } else if (connections[index].protocol == XTCP_PROTOCOL_UDP) {
      struct udp_pcb* udp_pcb = get_udp_pcb(index);
      if (udp_pcb != NULL) {
        memcpy(remote.ipaddr, &udp_pcb->remote_ip, sizeof(xtcp_ipaddr_t));
        remote.port_number = udp_pcb->remote_port;
      }
    }
  }
  return remote;
}

xtcp_remote_t get_local_from_pcb(int32_t index) {
  xtcp_remote_t remote = {.ipaddr = {0}, .port_number = 0};
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    if (connections[index].protocol == XTCP_PROTOCOL_TCP) {
      struct tcp_pcb* tcp_pcb = get_tcp_pcb(index);
      if (tcp_pcb != NULL) {
        memcpy(remote.ipaddr, &tcp_pcb->local_ip, sizeof(xtcp_ipaddr_t));
        remote.port_number = tcp_pcb->local_port;
      }
    } else if (connections[index].protocol == XTCP_PROTOCOL_UDP) {
      struct udp_pcb* udp_pcb = get_udp_pcb(index);
      if (udp_pcb != NULL) {
        memcpy(remote.ipaddr, &udp_pcb->local_ip, sizeof(xtcp_ipaddr_t));
        remote.port_number = udp_pcb->local_port;
      }
    }
  }
  return remote;
}

xtcp_remote_t get_remote(int32_t index) {
  xtcp_remote_t remote = {.ipaddr = {0}, .port_number = 0};
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (connections[index].pbuf != NULL)) {
    memcpy(remote.ipaddr, connections[index].pbuf->remote.ipaddr, sizeof(xtcp_ipaddr_t));
    remote.port_number = connections[index].pbuf->remote.port_number;
  }
  return remote;
}

xtcp_error_int32_t get_remote_data(int32_t index, uint8_t **data, int32_t length) {
  xtcp_error_int32_t result = {.status = XTCP_EINVAL, .value = -1};
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    struct pbuf *pbuf = connections[index].pbuf;
    if (pbuf != NULL) {
      int32_t copy_length = (length < pbuf->len) ? length : pbuf->len;
      *data = pbuf->payload;

      result.status = XTCP_SUCCESS;
      result.value = copy_length;
    }
  }
  return result;
}

int32_t free_remote_data(int32_t index) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    struct pbuf *pbuf = connections[index].pbuf;
    if (pbuf != NULL) {
      // Remove the first pbuf from the queue and free it
      uint16_t length = pbuf->len;
      connections[index].pbuf = pbuf->next;
      pbuf->next = NULL;
      pbuf_free(pbuf);

      if (connections[index].protocol == XTCP_PROTOCOL_TCP) {
        // For TCP we need to indicate to LwIP that we have processed the data
        struct tcp_pcb* tcp_pcb = get_tcp_pcb(index);
        if (tcp_pcb != NULL) {
          tcp_recved(tcp_pcb, length);
        }
      }
      return XTCP_SUCCESS;
    }
  }
  return XTCP_EINVAL;
}

xtcp_error_code_t unlink_remote(int32_t index, struct pbuf *pbuf) {
  xtcp_error_code_t result = XTCP_EINVAL;
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS) && (pbuf != NULL)) {
    struct pbuf *current;
    struct pbuf *previous = NULL;

    for (current = connections[index].pbuf; current != NULL; current = current->next) {
      if (current == pbuf) {
        // Found the pbuf to unlink
        if (previous == NULL) {
          // It's the first pbuf in the list
          connections[index].pbuf = current->next;
        } else {
          previous->next = current->next;
        }
        current->next = NULL;
        result = XTCP_SUCCESS;
        break;
      }
      previous = current;
    }
  }
  return result;
}

int32_t set_connection_client_data(int32_t index, void * unsafe data) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    connections[index].client_data = data;
    return XTCP_SUCCESS;
  }
  return XTCP_EINVAL;
}

void * unsafe get_connection_client_data(int32_t index) {
  if ((index >= 0) && (index < MAX_OPEN_SOCKETS)) {
    return connections[index].client_data;
  }
  return NULL;
}
