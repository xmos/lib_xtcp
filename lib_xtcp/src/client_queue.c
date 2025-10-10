// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "client_queue.h"

#include <string.h>

#include "debug_print.h"
#include "netif/configure.h"
#include "xtcp.h"

/* A 2D array of queue items */
static client_event_t client_queue[MAX_XTCP_CLIENTS][CLIENT_QUEUE_SIZE] = {{{.xtcp_event = 0, .id = 0}}};
static int32_t client_heads[MAX_XTCP_CLIENTS] = {0};
static int32_t client_num_events[MAX_XTCP_CLIENTS] = {0};

void xtcp_init_queue(void) {
  memset(client_queue, 0, sizeof(client_queue));
  memset(client_heads, 0, sizeof(client_heads));
  memset(client_num_events, 0, sizeof(client_num_events));
}

void renotify(unsigned client_num) {
  unsafe {
    if ((client_num < MAX_XTCP_CLIENTS) && (client_num_events[client_num] > 0)) {
      client_intf_notify(client_num);
    }
  }
}

client_event_t dequeue_event(unsigned client_num) {
  if ((client_num < MAX_XTCP_CLIENTS) && (client_num_events[client_num] > 0)) {
    // TODO - refactor queue implementation
    client_num_events[client_num]--;
    int32_t position = client_heads[client_num];
    client_heads[client_num] = (client_heads[client_num] + 1) % CLIENT_QUEUE_SIZE;
    return client_queue[client_num][position];
  } else {
    // Return a dummy event if the queue is empty
    client_event_t empty = {.xtcp_event = XTCP_EVENT_NONE, .id = -1};
    return empty;
  }
}

xtcp_error_code_t enqueue_event_and_notify(unsigned client_num, int32_t id, xtcp_event_type_t xtcp_event) {
  xtcp_error_code_t result = XTCP_EINVAL;
  if (client_num < MAX_XTCP_CLIENTS) {
    if (client_num_events[client_num] < CLIENT_QUEUE_SIZE) {
      unsigned position = (client_heads[client_num] + client_num_events[client_num]) % CLIENT_QUEUE_SIZE;
      client_queue[client_num][position].xtcp_event = xtcp_event;
      client_queue[client_num][position].id = id;

      client_num_events[client_num]++;

      client_intf_notify(client_num);
      result = XTCP_SUCCESS;
    } else {
      result = XTCP_ENOMEM;
    }
  }
  return result;
}

int32_t free_notifications_on_queue(unsigned client_num, int32_t id) {
  int32_t result = 0;

  if (client_num < MAX_XTCP_CLIENTS) {
    int32_t write_index = client_heads[client_num];
    int32_t read_index = client_heads[client_num];
    int32_t count = client_num_events[client_num];

    for (int32_t i = 0; i < count; ++i) {
      if (client_queue[client_num][read_index].id == id) {
        // Remove matches
        result += 1;
        // Found match on 'id', so remove this event from the queue
        client_num_events[client_num]--;

      } else {
        // Move non-matches to the write index
        if (write_index != read_index) {
          client_queue[client_num][write_index] = client_queue[client_num][read_index];
        }
        write_index += 1;
        if (write_index >= CLIENT_QUEUE_SIZE) {
          write_index = 0;
        }
      }
      read_index += 1;
      if (read_index >= CLIENT_QUEUE_SIZE) {
        read_index = 0;
      }
    }
  }
  return result;
}

__attribute__((weak)) void client_intf_notify(unsigned client_num) { (void)client_num; }
