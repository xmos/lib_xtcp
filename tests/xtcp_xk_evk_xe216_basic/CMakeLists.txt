cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(xtcp_xk_evk_xe216_basic)

set(APP_HW_TARGET           XCORE-200-EXPLORER)

# LwIP options needed for library build
set(LWIP_OPTS_PATH          "../lwip/contrib/ports/xmos/lib/standard")

set(APP_INCLUDES            ../common/include)

file(GLOB XC_SOURCES        RELATIVE ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
file(GLOB COMMON_SOURCES    RELATIVE ${CMAKE_CURRENT_LIST_DIR}
                                    "${CMAKE_CURRENT_LIST_DIR}/../common/src/*.xc")

list(APPEND XC_SOURCES ${COMMON_SOURCES})

set(APP_XC_SRCS ${XC_SOURCES})

set(APP_DEPENDENT_MODULES   lib_xtcp
                            "lib_board_support(1.4.0)"
                            "lib_logging(3.4.0)"
                            "lib_otpinfo(2.2.1)"
                            )

set(COMPILER_FLAGS_COMMON   -O3
                            -g
                            -mno-dual-issue
                            -Wall
                            -Wextra
                            -Wconversion
                            -Wdiv-by-zero
                            -Wfloat-equal
                            -Wsign-compare
                            -report
                            -DDEBUG_PRINT_ENABLE=1
                            -DDEBUG_PRINT_ENABLE_LIB_XTCP=1
                            -DXASSERT_ENABLE_DEBUG=1
                            -DBOARD_SUPPORT_BOARD=XK_EVK_XE216
                            )

# 1 process, 1 port
set(APP_COMPILER_FLAGS_1_1_UDP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_UDP)
set(APP_COMPILER_FLAGS_1_1_TCP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_TCP)
# 2 processes, 2 port
set(APP_COMPILER_FLAGS_2_2_UDP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=2 -DOPEN_PORTS_PER_PROCESS=2  -DPROTOCOL=XTCP_PROTOCOL_UDP)
set(APP_COMPILER_FLAGS_2_2_TCP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=2 -DOPEN_PORTS_PER_PROCESS=2  -DPROTOCOL=XTCP_PROTOCOL_TCP)
# 4 processes, 1 port
# set(APP_COMPILER_FLAGS_4_1_UDP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_UDP)
# set(APP_COMPILER_FLAGS_4_1_TCP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_TCP)
# 4 processes, 4 ports
# set(APP_COMPILER_FLAGS_4_4_UDP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=4  -DPROTOCOL=XTCP_PROTOCOL_UDP)
# set(APP_COMPILER_FLAGS_4_4_TCP_XK_EVK_XE216_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=4  -DPROTOCOL=XTCP_PROTOCOL_TCP)
# 1 process, 16 ports
# set(APP_COMPILER_FLAGS_1_16_UDP_XK_EVK_XE216_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=16 -DPROTOCOL=XTCP_PROTOCOL_UDP)
# set(APP_COMPILER_FLAGS_1_16_TCP_XK_EVK_XE216_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=16 -DPROTOCOL=XTCP_PROTOCOL_TCP)

set(APP_XSCOPE_SRCS         config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
