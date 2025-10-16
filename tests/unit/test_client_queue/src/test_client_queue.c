// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <unity.h>

#include "client_queue.h"

#define TEST_CLIENT_NUM 1
#define TEST_BAD_CLIENT_NUM (MAX_XTCP_CLIENTS + 1)
#define TEST_INDEX 7
#define OTHER_INDEX 8

#define UNSET -1

void setUp() { xtcp_init_queue(); }
void tearDown() {}

void test_enqueue_and_dequeue_same_data(void) {
  xtcp_event_type_t test_event = XTCP_NEW_CONNECTION;
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);

  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(test_event, result.xtcp_event);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
}

void test_enqueue_with_bad_client_num_leaves_queue_unchanged(void) {
  xtcp_event_type_t test_event = XTCP_NEW_CONNECTION;
  enqueue_event_and_notify(TEST_BAD_CLIENT_NUM, TEST_INDEX, test_event);

  // Attempt to dequeue from a valid client num, should be empty
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(XTCP_EVENT_NONE, result.xtcp_event);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_dequeue_from_empty_queue_reports_no_event(void) {
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(XTCP_EVENT_NONE, result.xtcp_event);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_dequeue_with_bad_client_num_reports_no_event(void) {
  client_event_t result = dequeue_event(TEST_BAD_CLIENT_NUM);
  TEST_ASSERT_EQUAL(XTCP_EVENT_NONE, result.xtcp_event);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_enqueue_with_bad_client_num_reports_EINVAL(void) {
  xtcp_event_type_t test_event = XTCP_NEW_CONNECTION;
  xtcp_error_code_t result = enqueue_event_and_notify(TEST_BAD_CLIENT_NUM, TEST_INDEX, test_event);
  TEST_ASSERT_EQUAL(XTCP_EINVAL, result);
}

void test_full_enqueue_ignores_new_events(void) {
  xtcp_event_type_t test_event = XTCP_NEW_CONNECTION;
  enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX), test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX + 1), test_event);
  // This should be ignored
  enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX + 2), XTCP_RECV_DATA);

  // Check data
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL((TEST_INDEX + 1), result.id);
  // Queue should now be empty
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_full_enqueue_reports_full(void) {
  xtcp_event_type_t test_event = XTCP_NEW_CONNECTION;
  enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX), test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX + 1), test_event);
  // This should be rejected
  xtcp_error_code_t result = enqueue_event_and_notify(TEST_CLIENT_NUM, (TEST_INDEX + 2), XTCP_RECV_DATA);
  TEST_ASSERT_EQUAL(XTCP_ENOMEM, result);
}

void test_renotify_with_bad_client_num(void) {
  // Not really a test, but just checking it doesn't crash
  renotify(100);
}

void test_free_notifications_from_tail_of_queue(void) {
  // Setup
  xtcp_event_type_t test_event = XTCP_RECV_DATA;
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, OTHER_INDEX, test_event);

  // Test
  free_notifications_on_queue(TEST_CLIENT_NUM, OTHER_INDEX);
  
  // Check data
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
  // Queue should now be empty
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_free_notifications_from_head_of_queue(void) {
  // Setup
  xtcp_event_type_t test_event = XTCP_RECV_DATA;
  enqueue_event_and_notify(TEST_CLIENT_NUM, OTHER_INDEX, test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);

  // Test
  free_notifications_on_queue(TEST_CLIENT_NUM, OTHER_INDEX);
  
  // Check data
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
  // Queue should now be empty
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_free_notifications_remove_none(void) {
  // Setup
  xtcp_event_type_t test_event = XTCP_RECV_DATA;
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);

  // Test
  free_notifications_on_queue(TEST_CLIENT_NUM, OTHER_INDEX);
  
  // Check data
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(TEST_INDEX, result.id);
  // Queue should now be empty
  result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}

void test_free_notifications_remove_all(void) {
  // Setup
  xtcp_event_type_t test_event = XTCP_RECV_DATA;
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);
  enqueue_event_and_notify(TEST_CLIENT_NUM, TEST_INDEX, test_event);

  // Test
  free_notifications_on_queue(TEST_CLIENT_NUM, TEST_INDEX);
  
  // Queue should now be empty
  client_event_t result = dequeue_event(TEST_CLIENT_NUM);
  TEST_ASSERT_EQUAL(UNSET, result.id);
}
