// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <stdlib.h>
#include <platform.h>
#include "xtcp.h"
#include "xtcp_blocking_client.h"
#include "smi.h"
#include "otp_board_info.h"
#include "debug_print.h"

port p_eth_rxclk  = on tile[1]: XS1_PORT_1J;
port p_eth_rxd    = on tile[1]: XS1_PORT_4E;
port p_eth_txd    = on tile[1]: XS1_PORT_4F;
port p_eth_rxdv   = on tile[1]: XS1_PORT_1K;
port p_eth_txen   = on tile[1]: XS1_PORT_1L;
port p_eth_txclk  = on tile[1]: XS1_PORT_1I;
port p_eth_int    = on tile[1]: XS1_PORT_1O;
port p_eth_rxerr  = on tile[1]: XS1_PORT_1P;
port p_eth_timing = on tile[1]: XS1_PORT_8C;

clock eth_rxclk   = on tile[1]: XS1_CLKBLK_1;
clock eth_txclk   = on tile[1]: XS1_CLKBLK_2;

port p_smi_mdc = on tile[1]: XS1_PORT_1N;
port p_smi_mdio = on tile[1]: XS1_PORT_1M;

otp_ports_t otp_ports = on tile[1]: OTP_PORTS_INITIALIZER;

#ifndef DEVICE_ADDRESS
#define DEVICE_ADDRESS 10,0,102,200
#endif

#ifndef HOST1_ADDRESS
#define HOST1_ADDRESS 10,0,102,42
#endif

#ifndef HOST2_ADDRESS
#define HOST2_ADDRESS 10,0,102,65
#endif

#define RUNTEST(name, x) debug_printf("*************************** " name " ***************************\n"); \
                              debug_printf("%s\n", (x) ? "PASSED" : "FAILED" )


#define ERROR debug_printf("ERROR: "__FILE__ ":%d\n", __LINE__);

xtcp_ipaddr_t host_addrs[] = {{HOST1_ADDRESS}, {HOST2_ADDRESS}};
int host_port = 49454;
int src_port = 49468;

// Static IP Config - change this to suit your network
xtcp_ipconfig_t ipconfig =
{
  {DEVICE_ADDRESS}, // ip address
  {255,255,255,0},   // netmask
  {0,0,0,0}        // gateway
};

int socket_send(chanend xtcp, xtcp_connection_t &conn, unsigned char buf[], int len) {
    return xtcp_write(xtcp, conn, buf, len);
}

int socket_receive(chanend xtcp, xtcp_connection_t &conn, unsigned char buf[], int len) {
    return xtcp_read(xtcp, conn, buf, len);
}


int socket_connect(chanend xtcp, xtcp_connection_t & conn, xtcp_ipaddr_t addr, int rport, xtcp_protocol_t protocol) {
    xtcp_connect(xtcp, rport, addr, protocol);

    slave xtcp_event(xtcp, conn);

    if (conn.event != XTCP_NEW_CONNECTION){
        debug_printf("Received event %d\n", conn.event);
        return 0;
    }

    debug_printf("Connected to %d\n", rport);

    return 1;
}

int socket_listen(chanend xtcp, xtcp_connection_t & conn, int lport, xtcp_protocol_t protocol) {
    xtcp_listen(xtcp, lport, protocol);

    slave xtcp_event(xtcp, conn);

    if (conn.event != XTCP_NEW_CONNECTION){
        ERROR;
        return 0;
    }

    debug_printf("New connection on port %d\n", conn.local_port);

    return 1;
}

int check_data(unsigned char data[], int len) {
    for (int i = 0; i < len; i++) {
        if (data[i] != i % 256){
            return 0;
        }
    }

    return 1;
}

void init_data(unsigned char data[], int len) {
    for (int i = 0; i < len; i++) {
        data[i] = i % 256;
    }
}

void zero_data(unsigned char data[], int len) {
    for (int i = 0; i < len; i++) {
        data[i] = 0;
    }
}

void wait(int ticks){
    timer tmr;
    int t;
    tmr :> t;
    tmr when timerafter(t + ticks) :> t;
}

int echo_client(chanend xtcp, xtcp_protocol_t protocol){
    unsigned char buf[1024];
    xtcp_connection_t conn;
    int len = 1024;
    int i = 0;

    wait(10000000);

    do{
        int rport = host_port + ++i;
        init_data(buf, len);
        if (!socket_connect(xtcp, conn, host_addrs[0], rport, protocol)){
            ERROR;
            return 0;
        }
        if (!socket_send(xtcp, conn, buf, len)){
            ERROR;
            return 0;
        }
        if (!socket_receive(xtcp, conn, buf, len)){
            ERROR;
            return 0;
        }
        if (!check_data(buf, len)){
            ERROR;
            return 0;
        }

        xtcp_close(xtcp, conn);

        slave xtcp_event(xtcp, conn);
        if (conn.event != XTCP_CLOSED){
            ERROR;
            return 0;
        }
    }while ((len /= 2));

    return 1;
}

int echo_client_multihost(chanend xtcp [], xtcp_protocol_t protocol, int hosts){
    unsigned char buf[2][1024];
    xtcp_connection_t conn[4];
    int len = 1024;

    for (int i=0;i<hosts;i++){
        init_data(buf[i], len);
    }
    wait(100000000);

    for (int i=0;i<hosts;i++){
        if (!socket_connect(xtcp[i], conn[i], host_addrs[i], host_port + (100 + i), protocol)){
            ERROR;
            return 0;
        }
    }
    for (int i=0;i<hosts;i++){
        if (!socket_send(xtcp[i], conn[i], buf[i], len)){
            ERROR;
            return 0;
        }
    }

    par{
        {
            socket_receive(xtcp[0], conn[0], buf[0], len);
            if (!check_data(buf[0], len)){
                ERROR;
            }
        }
        {
            socket_receive(xtcp[1], conn[1], buf[1], len);
            if (!check_data(buf[1], len)){
                ERROR;
            }
        }
    }

    for (int i=0;i<hosts;i++){
        xtcp_close(xtcp[i], conn[i]);
        slave xtcp_event(xtcp[i], conn[i]);
        if (conn[i].event != XTCP_CLOSED){
            ERROR;
            return 0;
        }
    }

    return 1;

}

int echo_server(chanend xtcp, xtcp_protocol_t protocol){
    unsigned char buf[1024];
    unsigned int rport;
    unsigned char raddr[4];
    xtcp_connection_t conn;
    int len = 1024;
    int i = 0;

    do{
        int lport = src_port + ++i;
        zero_data(buf, 1024);
        if (!socket_listen(xtcp, conn, lport, protocol)){
            return 0;
        }
        if (!socket_receive(xtcp, conn, buf, len)){
            ERROR;
            return 0;
        }
        rport = conn.remote_port;
        for (int j=0;j<4;j++){
            raddr[j] = conn.remote_addr[j];
        }

        xtcp_bind_remote(xtcp, conn, raddr, rport);

        if (!socket_send(xtcp, conn, buf, len)){
            ERROR;
            return 0;
        }

        xtcp_unlisten(xtcp, lport);
        xtcp_close(xtcp, conn);

        slave xtcp_event(xtcp, conn);
        if (conn.event != XTCP_CLOSED){
            ERROR;
            return 0;
        }
    }while ((len /= 2));

    return 1;
}

#define SPEED_TEST_DATA_SIZE 8192 * 10

int speed_test(chanend xtcp, xtcp_protocol_t protocol){
    unsigned char buf[4096];
    timer tmr;
    int t1, t2;
    xtcp_connection_t conn;
    int block_size;
    int bytes_to_send = SPEED_TEST_DATA_SIZE;

    if (protocol == XTCP_PROTOCOL_TCP){
        block_size = 4096;
    }else{
        block_size = XTCP_CLIENT_BUF_SIZE - 28; // - IP & UDP header
    }

    wait(100000000);

    if (!socket_connect(xtcp, conn, host_addrs[0], host_port, protocol)){
        ERROR;
        return 0;
    }

    init_data(buf, block_size);

    tmr :> t1;
    while (bytes_to_send > 0){
        socket_send(xtcp, conn, buf, block_size);
        bytes_to_send -= block_size;
    }
    tmr :> t2;

    t2 -= t1;
    t2 /= 100000;

    debug_printf("Sent %d bytes in ", SPEED_TEST_DATA_SIZE);

    if (t2 > 0){
        debug_printf("%d milliseconds\n", t2);
        t2 = SPEED_TEST_DATA_SIZE / t2;
        t2 *= 1000 * 8;
        debug_printf("%d bits per second\n", t2);
    }else{
        debug_printf("< 1 millisecond\n");
    }

    xtcp_close(xtcp, conn);

    slave xtcp_event(xtcp, conn);
    if (conn.event != XTCP_CLOSED){
        ERROR;
        return 0;
    }

    return 1;

}

int init(chanend xtcp[], int links){
    xtcp_connection_t conn;

    slave xtcp_event(xtcp[0], conn);
    if (conn.event != XTCP_IFDOWN){
        ERROR;
        return 0;
    }

    for (int i=0;i<links;i++){
        slave xtcp_event(xtcp[i], conn);
        if (conn.event != XTCP_IFUP){
            ERROR;
            return 0;
        }
    }

    return 1;
}

void runtests(chanend xtcp[], int links){
    RUNTEST("init", init(xtcp, links));
    RUNTEST("udp_server_test", echo_server(xtcp[0], XTCP_PROTOCOL_UDP));
    RUNTEST("udp_client_test", echo_client(xtcp[0], XTCP_PROTOCOL_UDP));
    RUNTEST("tcp_server_test", echo_server(xtcp[0], XTCP_PROTOCOL_TCP));
    RUNTEST("tcp_client_test", echo_client(xtcp[0], XTCP_PROTOCOL_TCP));
    RUNTEST("tcp_speed_test",  speed_test(xtcp[0], XTCP_PROTOCOL_TCP));
    RUNTEST("udp_speed_test",  speed_test(xtcp[0], XTCP_PROTOCOL_UDP));
    RUNTEST("multi host",      echo_client_multihost(xtcp, XTCP_PROTOCOL_TCP, 2));
    _Exit(0);
}

#define XTCP_MII_BUFSIZE 4096

int main(void)
{
    chan c_xtcp[2];
    mii_if i_mii;
    smi_if i_smi;

    par {
    on tile[1]: mii(i_mii, p_eth_rxclk, p_eth_rxerr, p_eth_rxd, p_eth_rxdv,
                    p_eth_txclk, p_eth_txen, p_eth_txd, p_eth_timing,
                    eth_rxclk, eth_txclk, XTCP_MII_BUFSIZE);

    on tile[1]: xtcp(c_xtcp, 1, i_mii,
                     null, null, null,
                     i_smi, 0,
                     null, otp_ports, ipconfig);

    // SMI/ethernet phy driver
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: runtests(c_xtcp, 2);

    }
    return 0;
}
