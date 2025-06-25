// Copyright 2017-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef _COMMON_H_
#define _COMMON_H_

#include <platform.h>
#include <stdlib.h>
#include <string.h>
#include <xassert.h>
#include <xtcp.h>

#include "debug_print.h"
#include "ethernet.h"
#include "otp_board_info.h"
#include "smi.h"

// Defines
#define RX_BUFFER_SIZE 1460
#define INCOMING_PORT 15533
#define INIT_VAL -1

#ifndef OPEN_PORTS_PER_PROCESS
#define OPEN_PORTS_PER_PROCESS 1
#endif

#ifndef REFLECT_PROCESSES
#define REFLECT_PROCESSES 1
#endif

#ifndef PROTOCOL
#define PROTOCOL XTCP_PROTOCOL_UDP
#endif

#define XTCP_MII_BUFSIZE (4096)
#define ETHERNET_SMI_PHY_ADDRESS (0)

// An enum to manage the array of connections from the ethernet component to its
// clients.
enum eth_clients { ETH_TO_XTCP, NUM_ETH_CLIENTS };

enum cfg_clients { CFG_TO_XTCP, CFG_TO_PHY_DRIVER, NUM_CFG_CLIENTS };

// Structure to hold connection state
typedef struct reflect_state_t {
  int active;   //< Whether this state structure is being used for a connection
  int conn_id;  //< The connection id
  xtcp_ipaddr_t remote_addr;  //< Host addrress, for UDP reconnect events
} reflect_state_t;

void udp_reflect(client xtcp_if i_xtcp, int start_port);

#endif
