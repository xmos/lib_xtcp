// Copyright 2011-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <ctype.h>
#include <platform.h>
#include <stdint.h>
#include <string.h>
#include <xs1.h>

/* XMOS library headers */
#define DEBUG_UNIT LIB_XTCP
#include "client_queue.h"
#include "debug_print.h"
#include "ethernet.h"
#include "mii.h"
#include "random.h"
#include "xassert.h"
#include "xtcp.h"
#include "xtcp_shim.h"

/* LWIP headers */
#include "lwip/arch.h"
#include "lwip/prot/ieee.h"
#include "netif/ethernetif.h"
#include "netif/xcore_netif_output.h"

/* XTCP headers */
#include "connection.h"
#include "lwip_shim.h"
#include "pbuf_shim.h"


void xtcp_lwip(server xtcp_if i_xtcp[n_xtcp], static const unsigned n_xtcp,
               client interface mii_if ?i_mii,
               client interface ethernet_cfg_if ?i_eth_cfg,
               client interface ethernet_rx_if ?i_eth_rx,
               client interface ethernet_tx_if ?i_eth_tx,
               const uint8_t (&?mac_address)[MACADDR_NUM_BYTES],
               otp_ports_t &?otp_ports,
               xtcp_ipconfig_t &ipconfig)
{
  timer timers[NUM_TIMEOUTS];
  uint32_t timeout[NUM_TIMEOUTS];
  uint32_t period[NUM_TIMEOUTS];
  uint8_t mac_address_phy[MACADDR_NUM_BYTES];
  mii_info_t mii_info;

  /* Prepare the period value before calling xcore_lwip_init_timers() */
  for (int i = 0; i < NUM_TIMEOUTS; ++i) {
    period[i] = XS1_TIMER_KHZ;
  }

  if (!isnull(mac_address)) {
    memcpy(mac_address_phy, mac_address, MACADDR_NUM_BYTES);
  } else if (!isnull(otp_ports)) {
    otp_board_info_get_mac(otp_ports, 0, mac_address_phy);
  } else {
    fail("Must supply OTP ports or MAC address to xtcp component");
  }

  if (!isnull(i_eth_cfg) && !isnull(i_mii)) {
    fail("Error: Cannot use both ethernet_cfg_if and mii_if at the same time");
  } else if (isnull(i_eth_cfg) && isnull(i_mii)) {
    fail("Error: Specify one of the following combinations, ethernet_cfg_if/ethernet_rx_if/ethernet_tx_if or mii_if");
  }

  xcore_netif_output_init(i_eth_tx, i_mii);

  if (!isnull(i_eth_cfg)) {
    i_eth_cfg.set_macaddr(0, mac_address_phy);

    size_t index = i_eth_rx.get_index();
    ethernet_macaddr_filter_t macaddr_filter;
    memcpy(macaddr_filter.addr, mac_address_phy, MACADDR_NUM_BYTES);
    i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

    // Add broadcast filter, needed for ARP
    memset(macaddr_filter.addr, 0xff, MACADDR_NUM_BYTES);
    i_eth_cfg.add_macaddr_filter(index, 0, macaddr_filter);

    // Only allow ARP and IP packets to the stack
    i_eth_cfg.add_ethertype_filter(index, ETHTYPE_ARP);
    i_eth_cfg.add_ethertype_filter(index, ETHTYPE_IP);

  } else if (!isnull(i_mii)) {
    mii_info = i_mii.init();
  }

  xarch_init();
  xcore_ethernetif_init(mac_address_phy, &ipconfig);
  client_init_notification(n_xtcp, i_xtcp);
  xtcp_init_queue();
  init_client_connections();

  unsigned time_now;
  timers[0] :> time_now;
  xcore_lwip_init_timers(period, timeout, time_now);

  int32_t netif_notify_state = 0;

  while (1) {
    select {
      case !isnull(i_eth_rx) => i_eth_rx.packet_ready(): {
        uint8_t buffer[ETHERNET_MAX_PACKET_SIZE];
        ethernet_packet_info_t desc;

        i_eth_rx.get_packet(desc, buffer, ETHERNET_MAX_PACKET_SIZE);

        if (desc.type == ETH_DATA) {
          ethernetif_input(buffer, desc.len);

        } else if (desc.type == ETH_IF_STATUS) {
          if (buffer[0] == ETHERNET_LINK_UP) {
            xcore_net_link_up();
          } else {
            xcore_net_link_down();
            // Notify link down
            netif_notify_state = 0;
            for (unsigned i = 0; i < n_xtcp; ++i) {
              (void)enqueue_event_and_notify(i, 0, XTCP_IFDOWN);
            }
          }
        }
        break;
      }

      case !isnull(i_mii) => mii_incoming_packet(mii_info):
        int * unsafe data;
        do {
          int nbytes;
          unsigned timestamp;
          {data, nbytes, timestamp} = i_mii.get_incoming_packet();
          if (data) {
            ethernetif_input((uint8_t *)data, nbytes);
            i_mii.release_packet(data);
          }
        } while (data != NULL);
        break;
        
      /* Client calls get_event() after the server has notified with event_ready().
       * This function pops the event and updates with latest values */
      case i_xtcp[unsigned i].get_event(int32_t &id) -> xtcp_event_type_t event:
        client_event_t head = dequeue_event(i);

        event = head.xtcp_event;
        id = head.id;

        renotify(i);
        break;
        
      case i_xtcp[unsigned i].socket(xtcp_protocol_t protocol) -> int32_t result:
        xtcp_error_int32_t connection = shim_new_socket(i, protocol);
        if (connection.status != XTCP_SUCCESS) {
          // No free client connection available
          result = connection.status;
        } else {
          result = connection.value;
        }
        break;

      case i_xtcp[unsigned i].close(int32_t id):
        shim_close_socket(i, id);
        break;

      case i_xtcp[unsigned i].abort(int32_t id):
        shim_close_socket(i, id);
        // TODO implement abort
      break;

      case i_xtcp[unsigned i].listen(int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr) -> xtcp_error_code_t result:
        xtcp_ipaddr_t local;
        memcpy(local, ipaddr, sizeof(xtcp_ipaddr_t));
        result = shim_listen(i, id, port_number, local);
        break;
        
      case i_xtcp[unsigned i].connect(int32_t id, uint16_t port_number, xtcp_ipaddr_t ipaddr) -> xtcp_error_code_t result:
        xtcp_ipaddr_t remote_addr;
        memcpy(remote_addr, ipaddr, sizeof(xtcp_ipaddr_t));
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else {
          // Connection is active, so we can proceed
          result = shim_connect(i, id, port_number, remote_addr);
        }
        break;

      case i_xtcp[unsigned i].send(int32_t id, const uint8_t buffer[length], uint32_t length) -> int32_t result:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else {
          // Connection is active, so we can proceed
          unsafe {
            void* unsafe buffer_token = pbuf_shim_alloc_tx(length);
            if (buffer_token == NULL) {
              result = XTCP_ENOMEM;
            } else {
              memcpy(pbuf_shim_token_payload(buffer_token), buffer, length);
              result = shim_send(i, id, buffer_token);
            }
          }
        }
        break;

      case i_xtcp[unsigned i].sendto(int32_t id, const uint8_t buffer[length], uint32_t length, xtcp_ipaddr_t remote_addr, uint16_t remote_port) -> int32_t result:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else if (get_protocol(id) == XTCP_PROTOCOL_TCP) {
          // TCP does not support sendto
          result = XTCP_EPROTONOSUPPORT;
        } else {
          // Connection is active, so we can proceed
          xtcp_ipaddr_t remote_addr_copy;
          memcpy(remote_addr_copy, remote_addr, sizeof(xtcp_ipaddr_t));
          unsafe {
            void* unsafe buffer_token = pbuf_shim_alloc_tx(length);
            if (buffer_token == NULL) {
              result = XTCP_ENOMEM;
            } else {
              memcpy(pbuf_shim_token_payload(buffer_token), buffer, length);
              result = shim_sendto(i, id, buffer_token, remote_addr_copy, remote_port);
            }
          }
        }
        break;

      case i_xtcp[unsigned i].recv(int32_t id, uint8_t buffer[length], uint32_t length) -> int32_t result:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else {
          uint8_t * unsafe data = NULL;
          xtcp_error_int32_t copy_length;
          unsafe {
            copy_length = get_remote_data(id, &data, length);
          }
          if (copy_length.status != XTCP_SUCCESS) {
            // Error in getting remote data
            result = copy_length.status;
          } else {
            // copy_length.value is pbuf->len
            result = copy_length.value;
            unsafe {
              memcpy(buffer, data, copy_length.value);
            }
          }
          (void)free_remote_data(id);
        }
        break;

      case i_xtcp[unsigned i].recvfrom(int32_t id, uint8_t buffer[length], uint32_t length, xtcp_ipaddr_t &ipaddr, uint16_t &port_number) -> int32_t result:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else if (get_protocol(id) == XTCP_PROTOCOL_TCP) {
          // TCP does not support recvfrom
          result = XTCP_EPROTONOSUPPORT;
        } else {
          // Connection is active, so we can proceed
          xtcp_host_t remote = get_remote(id);
          memcpy(ipaddr, remote.ipaddr, sizeof(xtcp_ipaddr_t));
          port_number = remote.port_number;

          /* This is currently expecting data in only one pbuf, so no chaining
           * If memory pool config in lwipopts.h is ever changed then this needs to change */
          uint8_t * unsafe data = NULL;
          xtcp_error_int32_t copy_length;
          unsafe {
            copy_length = get_remote_data(id, &data, length);
          }
          if (copy_length.status != XTCP_SUCCESS) {
            // Error in getting remote data
            result = copy_length.status;
          } else {
            // copy_length.value is pbuf->len
            result = copy_length.value;
            unsafe {
              memcpy(buffer, data, copy_length.value);
            }
          }
          (void)free_remote_data(id);
        }
        break;

      case i_xtcp[unsigned i].set_connection_client_data(int32_t id, void *unsafe data) -> int32_t result:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          result = connection.status;
        } else {
          result = set_connection_client_data(id, data);
        }
        break;

      case i_xtcp[unsigned i].get_connection_client_data(int32_t id) -> void *unsafe data:
        xtcp_error_int32_t connection = find_client_connection(i, id);
        if (connection.status != XTCP_SUCCESS) {
          // Bad parameter or inactive connection
          data = NULL;
        } else {
          data = get_connection_client_data(id);
        }
        break;

      case i_xtcp[unsigned i].join_multicast_group(xtcp_ipaddr_t addr):
        xtcp_ipaddr_t group_addr;
        memcpy(group_addr, addr, sizeof(xtcp_ipaddr_t));
        shim_join_multicast_group(group_addr);
        break;

      case i_xtcp[unsigned i].leave_multicast_group(xtcp_ipaddr_t addr):
        xtcp_ipaddr_t group_addr;
        memcpy(group_addr, addr, sizeof(xtcp_ipaddr_t));
        shim_leave_multicast_group(group_addr);
        break;

      case i_xtcp[unsigned i].request_host_by_name(const uint8_t hostname[len], static const unsigned len, xtcp_ipaddr_t dns_server) -> xtcp_host_t result:
        xtcp_ipconfig_t xipaddr = xcore_netif_get_ipconfig();
        if (xipaddr.gateway[0] != 0) {
          uint8_t hostname_copy[len];
          memcpy(hostname_copy, hostname, len);
          xtcp_ipaddr_t dns;
          memcpy(dns, dns_server, sizeof(xtcp_ipaddr_t));

          result = shim_request_host_by_name(i, hostname_copy, dns);
        } else {
          debug_printf("xtcp.request_host_by_name: No gateway configured\n");
          memset(result.ipaddr, 0, sizeof(xtcp_ipaddr_t));
          result.port_number = 0;
        }
        break;

      case i_xtcp[unsigned i].get_netif_ipconfig(int32_t netif_id) -> xtcp_ipconfig_t ipconfig:
        ipconfig = xcore_netif_get_ipconfig();
        break;

      case i_xtcp[unsigned i].get_ipconfig_remote(int32_t id) -> xtcp_host_t ipaddr:
        ipaddr = get_remote_from_pcb(id);
        break;

      case i_xtcp[unsigned i].get_ipconfig_local(int32_t id) -> xtcp_host_t ipaddr:
        ipaddr = get_local_from_pcb(id);
        break;

      case i_xtcp[unsigned i].is_ifup(void) -> int result:
        result = get_if_state();
        break;

      case (size_t i = 0; i < NUM_TIMEOUTS; i++)
        timers[i] when timerafter(timeout[i]) :> unsigned current:
      {
        xcore_timeout(i);

        if (i == 0) {
          if (ethernetif_has_ip_address() == XTCP_SUCCESS) {
          
            if ((netif_notify_state == 0) && get_if_state()) {
              netif_notify_state = 1;
              for (unsigned i = 0; i < n_xtcp; ++i) {
                (void)enqueue_event_and_notify(i, 0, XTCP_IFUP);
              }
            }
          }
        }
        timeout[i] += period[i];
        break;
      }
    }
  }
}
