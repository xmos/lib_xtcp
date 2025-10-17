cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(xtcp_burst)

include(${CMAKE_CURRENT_LIST_DIR}/../board_support/board_support.cmake)

set(APP_HW_TARGET           xk-eth-xu316-dual-100m.xn)

# LwIP options needed for library build
set(LWIP_OPTS_PATH          "../lwip/contrib/ports/xmos/lib/standard")

set(APP_INCLUDES            ../common/include ${test_board_support_INC})

file(GLOB XC_SOURCES        RELATIVE ${CMAKE_CURRENT_LIST_DIR} "src/*.xc")
file(GLOB COMMON_SOURCES    RELATIVE ${CMAKE_CURRENT_LIST_DIR}
                                    "${CMAKE_CURRENT_LIST_DIR}/../common/src/*.xc")

list(APPEND XC_SOURCES ${COMMON_SOURCES})

set(APP_XC_SRCS ${XC_SOURCES} ${test_board_support_SRCS})

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

# Multi-PHY Options
# Default build is for dual PHY xcore-ai board
# If you need single PHY xcore-ai add '-DSINGLE_PHY=1' on cmake command line
if(DEFINED SINGLE_PHY)
set(PHY_FLAGS               -DXCORE_AI_MULTI_PHY_SINGLE_PHY=SINGLE_PHY)
else()
set(PHY_FLAGS               -DXCORE_AI_MULTI_PHY_DUAL_PHY=1)
endif()

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
                            -DTEST_BOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M
                            ${PHY_FLAGS})

# 1 process, 1 port
set(APP_COMPILER_FLAGS_1_1_UDP_XMS0020_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_UDP -DBUSY=100)
set(APP_COMPILER_FLAGS_1_1_TCP_XMS0020_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_TCP -DBUSY=100)
# 2 processes, 2 port
set(APP_COMPILER_FLAGS_2_2_UDP_XMS0020_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=2 -DOPEN_PORTS_PER_PROCESS=2  -DPROTOCOL=XTCP_PROTOCOL_UDP -DBUSY=100)
set(APP_COMPILER_FLAGS_2_2_TCP_XMS0020_ETH     ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=2 -DOPEN_PORTS_PER_PROCESS=2  -DPROTOCOL=XTCP_PROTOCOL_TCP -DBUSY=100)
# 4 processes, 1 port
# set(APP_COMPILER_FLAGS_4_1_UDP_XMS0020_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_UDP -DBUSY=100)
# set(APP_COMPILER_FLAGS_4_1_TCP_XMS0020_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=1  -DPROTOCOL=XTCP_PROTOCOL_TCP -DBUSY=100)
# 4 processes, 4 ports
# set(APP_COMPILER_FLAGS_4_4_UDP_XMS0020_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=4  -DPROTOCOL=XTCP_PROTOCOL_UDP -DBUSY=100)
# set(APP_COMPILER_FLAGS_4_4_TCP_XMS0020_ETH    ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=4 -DOPEN_PORTS_PER_PROCESS=4  -DPROTOCOL=XTCP_PROTOCOL_TCP -DBUSY=100)
# 1 process, 16 ports
# set(APP_COMPILER_FLAGS_1_16_UDP_XMS0020_ETH   ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=16 -DPROTOCOL=XTCP_PROTOCOL_UDP -DBUSY=100)
# set(APP_COMPILER_FLAGS_1_16_TCP_XMS0020_ETH   ${COMPILER_FLAGS_COMMON} -DREFLECT_PROCESSES=1 -DOPEN_PORTS_PER_PROCESS=16 -DPROTOCOL=XTCP_PROTOCOL_TCP -DBUSY=100)

set(APP_XSCOPE_SRCS         config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
