// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <unity.h>

#include "connection.h"

#define TEST_CLIENT_NUM 0

// #define UNSET -1

void setUp(){
    init_client_connections();
}
void tearDown(){}

void test_new_list_is_empty(void) {
    // Test that checking the first index reports inactive
    xtcp_error_int32_t active = is_active(0);
    TEST_ASSERT_FALSE(active.value);
}

void test_first_connection_gives_zero_index(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    // Test that assigning connection from new list returns index 0, first item/index
    TEST_ASSERT_EQUAL(0, connection.value);
}

void test_assign_connection_reports_active(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    xtcp_error_int32_t active = is_active(connection.value);
    TEST_ASSERT_TRUE(active.value);
}

void test_out_of_range_index_reports_fail(void) {
    int32_t wild_index = 999;
    xtcp_error_int32_t active = is_active(wild_index);
    TEST_ASSERT_EQUAL(XTCP_EINVAL, active.status);
}

void test_assign_two_connections_passes(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    xtcp_error_int32_t connection2 = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection2.status);
    TEST_ASSERT_NOT_EQUAL_INT32(connection.value, connection2.value);
}

void test_assign_connection_then_find_succeeds(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    // Test that finding the connection we just assigned returns the same index
    xtcp_error_int32_t found = find_client_connection(TEST_CLIENT_NUM, connection.value);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, found.status);
    TEST_ASSERT_EQUAL(connection.value, found.value);
}

void test_assign_connection_then_get_client_matches(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    TEST_ASSERT_EQUAL(TEST_CLIENT_NUM, get_client_info(connection.value));
}

void test_assign_connection_then_free_reports_inactive(void) {
    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    xtcp_error_int32_t active = is_active(connection.value);
    TEST_ASSERT_TRUE(active.value);
    // Test
    free_client_connection(connection.value);
    // Index is technically invalid after free, but we can still check active state here
    active = is_active(connection.value);
    TEST_ASSERT_FALSE(active.value);
}

void test_set_remote_then_get_remote_matches(void) {

#define PAYLOAD_LENGTH 8
    uint8_t pbuf_payload[PAYLOAD_LENGTH] = {0};
    struct pbuf pbuf = {.payload = pbuf_payload, .len = PAYLOAD_LENGTH, .tot_len = PAYLOAD_LENGTH}; // Dummy pbuf for test
    const xtcp_ipaddr_t test_addr = {192, 168, 1, 100};
    ip_addr_t test_set_addr;
    const uint16_t test_port = 8080;
    uint8_t *test_payload = NULL;
    int32_t test_length = 44;

    memcpy(&test_set_addr, &test_addr, sizeof(ip_addr_t));

    xtcp_error_int32_t connection = assign_client_connection(TEST_CLIENT_NUM, XTCP_PROTOCOL_TCP);
    TEST_ASSERT_EQUAL(XTCP_SUCCESS, connection.status);
    // Assign remote state
    (void)set_remote(connection.value, &test_set_addr, test_port, &pbuf);

    // Retrieve and test remote state
    xtcp_host_t remote = get_remote(connection.value);
    TEST_ASSERT_EQUAL(test_port, remote.port_number);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(test_addr, remote.ipaddr, 4);

    xtcp_error_int32_t get_result = get_remote_data(connection.value, &test_payload, test_length, NULL);
    TEST_ASSERT_EQUAL(PAYLOAD_LENGTH, get_result.value);
    TEST_ASSERT_EQUAL_UINT32(pbuf_payload, test_payload);
}
