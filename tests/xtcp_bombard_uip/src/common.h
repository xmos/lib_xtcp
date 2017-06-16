#ifndef _COMMON_H_
#define _COMMON_H_

#include <platform.h>
#include <string.h>
#include "debug_print.h"
#include <xtcp.h>
#include "xtcp_stack.h"
#include <stdlib.h>
#include <xassert.h>

#include "otp_board_info.h"
#include "ethernet.h"
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

// An enum to manage the array of connections from the ethernet component
// to its clients.
enum eth_clients {
  ETH_TO_XTCP,
  NUM_ETH_CLIENTS
};

enum cfg_clients {
  CFG_TO_XTCP,
  CFG_TO_PHY_DRIVER,
  NUM_CFG_CLIENTS
};

// Structure to hold connection state
typedef struct reflect_state_t {
  int active;      //< Whether this state structure is being used
                   //  for a connection
  int conn_id;     //< The connection id
} reflect_state_t;

void udp_reflect(client xtcp_if i_xtcp, int start_port);

#endif
