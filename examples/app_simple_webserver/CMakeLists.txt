cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_simple_webserver)

set(APP_HW_TARGET          xk-eth-316-dual.xn)

# LwIP options needed for library build
set(LWIP_OPTS_PATH          "../lwip/contrib/ports/xmos/lib/standard")

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE OFF)

set(APP_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue
                            -Wall
                            -Wextra
                            -Wconversion
                            -Wdiv-by-zero
                            -Wfloat-equal
                            -Wsign-compare
                            -report
                            -DBOARD_SUPPORT_BOARD=XK_ETH_316_DUAL
                            -DDEBUG_PRINT_ENABLE=1
                            -DDEBUG_PRINT_ENABLE_LIB_XTCP=1
                            -DDEBUG_PRINT_ENABLE_xk_eth_316_dual=1
                            -DXASSERT_ENABLE_DEBUG=1)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
