// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#define DEBUG_UNIT LIB_XTCP

#include "tcp_transport.h"

/* Lwip headers */
#include "lwip/netif.h"
#include "lwip/stats.h"
#include "lwip/tcp.h"

/* XMOS library headers */
#include "client_queue.h"
#include "connection.h"
#include "debug_print.h"
#include "lwip_shim.h"


#if LWIP_EVENT_API == 1
/* Function called by lwIP when any TCP event happens on a connection */
err_t lwip_tcp_event(void *arg, struct tcp_pcb *pcb, enum lwip_event e, struct pbuf *p, u16_t size, err_t err) {
  (void)size;

  err_t result = ERR_OK;

  int32_t index = (int32_t)arg;  // arg is the index in the connection array

  if ((index < 0) || (index >= MAX_OPEN_SOCKETS)) {
    result = ERR_MEM;
    return result;
  }

  unsigned client_num = get_client_info(index);

  switch (e) {
    case LWIP_EVENT_ACCEPT: {
      // Called with (pcb->callback_arg, NULL, LWIP_EVENT_ACCEPT, NULL, 0, ERR_MEM), if memory error creating a socket
      // from the listenter. Called with (pcb->callback_arg, pcb,  LWIP_EVENT_ACCEPT, NULL, 0, ERR_OK), if successfully
      // created socket. Returns:
      //  - ERR_OK: Connection accepted.
      //  - ERR_ABRT: Aborts the connection and we must call tcp_abort() and free the pcb/pbuf.
      //  - any other err_t: LwIP actions abort of the connection.

      if ((err != ERR_OK) || (pcb == NULL)) {
        /* LwIP failed to create new socket while trying to accept connection. */
        result = ERR_VAL;
      } else {
        /* Lowering the PCB priority allows older connections to be aborted to be able to accept newer connections. */
        tcp_setprio(pcb, TCP_PRIO_MIN);

        xtcp_error_int32_t accepted = shim_accept(client_num, pcb, index);
        if (accepted.status != XTCP_SUCCESS) {
          // debug_printf("shim_accept failed: %d\n", accepted.status);
          result = ERR_MEM;
        } else {
          xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, accepted.value, XTCP_ACCEPTED);
          if (enqueue != XTCP_SUCCESS) {
            debug_printf("lwip_tcp_event: accept failed: %d\n", enqueue);
            result = ERR_INPROGRESS; // Have lwip abort the connection
          } else {
            result = ERR_OK;
          }
        }
      }
      break;
    }

    case LWIP_EVENT_CONNECTED: {
      // Called with (pcb->callback_arg, pcb, LWIP_EVENT_CONNECTED, NULL, 0, ERR_OK)
      // Returns:
      //  - ERR_OK: Connection acked.
      //  - ERR_ABRT: Aborts the connection and we must call tcp_abort() and free the pcb/pbuf.

      xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, index, XTCP_NEW_CONNECTION);
      if (enqueue != XTCP_SUCCESS) {
        debug_printf("lwip_tcp_event: connected failed to queue event: %d\n", enqueue);
        // TODO - should we abort the connection here?
        
      } else {
        result = ERR_OK;
      }
      break;
    }

    case LWIP_EVENT_RECV: {
      // Called with (pcb->callback_arg, pcb, LWIP_EVENT_RECV, refused_data, 0, ERR_OK)
      // Called with (pcb->callback_arg, pcb, LWIP_EVENT_RECV, recv_data, 0, ERR_OK)
      // Closed,     (pcb->callback_arg, pcb, LWIP_EVENT_RECV, NULL,      0, ERR_OK)
      // Returns:
      //  - ERR_OK: Data received or connection closed. The pbuf is freed by lwIP.
      //  - ERR_ABRT: Aborts the connection and we must call tcp_abort() and free the pcb/pbuf.
      //  - any other err_t: Data 'refused', the pbuf will be retried in future.

      if (p == NULL) {
        // Closed by remote host
        xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, index, XTCP_CLOSED);
        if (enqueue != XTCP_SUCCESS) {
          debug_printf("lwip_tcp_event: CLOSE event lost: %d\n", enqueue);
        }
        result = ERR_OK;

      } else {
        set_remote(index, NULL, 0, p);

        xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, index, XTCP_RECV_DATA);
        if (enqueue != XTCP_SUCCESS) {
          debug_printf("lwip_tcp_event: RECV failed: %d\n", enqueue);
          xtcp_error_code_t unlink = unlink_remote(index, p);
          if (unlink != XTCP_SUCCESS) {
            debug_printf("lwip_tcp_event: RECV unlink failed: %d\n", unlink);
          } else {
            debug_printf("lwip_tcp_event: RECV unlink succeeded: %d\n", unlink);
          }
          result = ERR_INPROGRESS; // refuse data as queue failed
        } else {
          result = ERR_OK;
        }
      }
      break;
    }

    case LWIP_EVENT_SENT: {
      // Called with (pcb->callback_arg, pcb, LWIP_EVENT_SENT, NULL, space, ERR_OK)
      // Returns:
      //  - ERR_ABRT: Aborts the connection and we must call tcp_abort() and free the pcb/pbuf.
      //  - any other err_t: 'OK'.

      // debug_printf("sent: %d, %d\n", pcb->local_port, size);

      xtcp_error_code_t enqueue = enqueue_event_and_notify(client_num, index, XTCP_SENT_DATA);
      if (enqueue != XTCP_SUCCESS) {
        debug_printf("lwip_tcp_event: SENT event lost: %d\n", enqueue);
      }
      result = ERR_OK;
      break;
    }

    case LWIP_EVENT_ERR: {
      // Called with (pcb->callback_arg, NULL, LWIP_EVENT_ERR, NULL, 0, ERR_CLSD), lwip will clean up PCB after.
      // Called with (pcb->callback_arg, NULL, LWIP_EVENT_ERR, NULL, 0, ERR_ABRT), local abort, notify client,
      // Warning: lwip has ALREADY freed PCB.
      // Called with (pcb->callback_arg, NULL, LWIP_EVENT_ERR, NULL, 0, ERR_RST), remote host reset connection,
      // notify client, lwip will clean up PCB after. Returns: ignored

      xtcp_error_code_t enqueue = XTCP_EINVAL;
      debug_printf("LWIP_EVENT_ERR: %s\n", lwip_strerr(err));
      if (err == ERR_ABRT) {
        enqueue = enqueue_event_and_notify(client_num, index, XTCP_ABORTED);

      } else if ((err == ERR_RST) || (err == ERR_CLSD)) {
        enqueue = enqueue_event_and_notify(client_num, index, XTCP_TIMED_OUT);

      } else {
        debug_printf("Unknown Connection %d error: %d\n", index, err);
      }

      if (enqueue != XTCP_SUCCESS) {
        debug_printf("lwip_tcp_event: ERR event lost: %d (%d)\n", enqueue, err);
      }

      // do we free here, the application then has no connection to reference?
      free_client_connection(index);
      result = ERR_OK;
      break;
    }

    case LWIP_EVENT_POLL: {
      // Called from tcp_slowtmr()
      // Called with (pcb->callback_arg, pcb, LWIP_EVENT_POLL, NULL, 0, ERR_OK)
      // Returns:
      //  - ERR_OK: Happy, LwIP will attempt to send more data.
      //  - ERR_ABRT: Aborts the connection and we must call tcp_abort() and free the pcb/pbuf.

      result = ERR_OK;
      break;
    }
  }
  return result;
}
#endif /* LWIP_EVENT_API == 1 */

// static void tcpecho_raw_free(struct tcpecho_raw_state *es) {
//   if (es != NULL) {
//     if (es->p) {
//       /* free the buffer chain if present */
//       pbuf_free(es->p);
//     }

//     mem_free(es);
//   }
// }

// static void tcpecho_raw_close(struct tcp_pcb *tpcb) {
//   debug_printf("close: %d\n", tpcb->local_port);

//   // tcpecho_raw_free(es);

//   tcp_close(tpcb);
// }

// static void tcpecho_raw_send(struct tcp_pcb *tpcb, struct tcpecho_raw_state *es) {
//   struct pbuf *ptr;
//   err_t wr_err = ERR_OK;

//   while ((wr_err == ERR_OK) && (es->p != NULL) && (es->p->len <= tcp_sndbuf(tpcb))) {
//     ptr = es->p;

//     /* enqueue data for transmission */
//     wr_err = tcp_write(tpcb, ptr->payload, ptr->len, 1);
//     if (wr_err == ERR_OK) {
//       u16_t plen;

//       plen = ptr->len;
//       /* continue with next pbuf in chain (if any) */
//       es->p = ptr->next;
//       if (es->p != NULL) {
//         /* new reference! */
//         pbuf_ref(es->p);
//       }
//       /* chop first pbuf from chain */
//       pbuf_free(ptr);
//       /* we can read more data now */
//       tcp_recved(tpcb, plen);
//     } else if (wr_err == ERR_MEM) {
//       /* we are low on memory, try later / harder, defer to poll */
//       es->p = ptr;
//     } else {
//       /* other problem ?? */
//     }
//   }
// }
