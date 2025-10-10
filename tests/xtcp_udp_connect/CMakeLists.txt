cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(xtcp_udp_connect)

include(${CMAKE_CURRENT_LIST_DIR}/../board_support/board_support.cmake)

set(APP_HW_TARGET           xk-eth-xu316-dual-100m.xn)

# LwIP options needed for library build
set(LWIP_OPTS_PATH          "lwip/contrib/ports/xmos/lib/standard")

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

set(APP_COMPILER_FLAGS      -O3
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
                            -DTEST_BOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
