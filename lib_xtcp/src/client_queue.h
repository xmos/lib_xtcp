// Copyright 2016-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef CLIENT_QUEUE_H
#define CLIENT_QUEUE_H

#include "xtcp.h"

/** Client queue item, this is used to send events through the xtcp interface to the client application */
typedef struct client_event_s {
  xtcp_event_type_t xtcp_event; /*!< XTCP event to notify the client of */
  int32_t id; /*!< Connection identifier the event relates to */
} client_event_t;

/** Initialize the client event queue */
void xtcp_init_queue(void);

/** Renotify a client about pending events
 * 
 * \param client_num The client to notify if there are pending events.
 */
void renotify(unsigned client_num);

/** Dequeue an event from a client's event queue 
 * 
 * \param client_num The client to dequeue an event for.
 * 
 * \returns The event at the head of the client's event queue, or XTCP_EVENT_NONE if the queue is empty.
 */
client_event_t dequeue_event(unsigned client_num);

/** Enqueue an event for a client and notify them 
 * 
 * \param client_num  The client to enqueue an event for.
 * \param id          The connection identifier the event relates to.
 * \param xtcp_event  The event to enqueue.
 * 
 * \retval XTCP_SUCCESS If the event was successfully enqueued.
 * \retval XTCP_ENOMEM  If the client's event queue is full, the event will be dropped.
 * \retval XTCP_EINVAL  If the client number is invalid.
 */
xtcp_error_code_t enqueue_event_and_notify(unsigned client_num, int32_t id, xtcp_event_type_t xtcp_event);

/** Free any pending notifications on a client's event queue for a particular connection
 * 
 * This is typically used during close/abort to remove any pending events for a connection that is being closed.
 *
 * It attempts to scan the queue and remove any events for the given connection identifier. This is to avoid having event 
 * notifications appear after a connection has been closed.
 *
 * \param client_num  The client to free notifications for.
 * \param id          The connection identifier to free notifications for.
 * 
 * \returns The number of events freed, or XTCP_EINVAL if the client number is invalid.
 * 
 */
int32_t free_notifications_on_queue(unsigned client_num, int32_t id);

#ifndef __XC__
/**
 * Configure callback called during TCP/IP stack operations when events occur that require client notification.
 * Function defined as weak, define this function in the client application to add custom configuration.
 * 
 * \param client_num The client number to notify.
 */
void client_intf_notify(unsigned client_num) __attribute__((weak));
#endif /* __XC__ */

#endif /* CLIENT_QUEUE_H */
