cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_simple_webserver)

set(APP_HW_TARGET          xk-eth-xu316-dual-100m.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

# Multi-PHY Options
# Default build is for dual PHY xcore-ai board
# If you need single PHY xcore-ai add '-DSINGLE_PHY=1' on cmake command line
if(DEFINED SINGLE_PHY)
set(PHY_FLAGS               -DXCORE_AI_MULTI_PHY_SINGLE_PHY=SINGLE_PHY)
else()
set(PHY_FLAGS               -DXCORE_AI_MULTI_PHY_DUAL_PHY=1)
endif()

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -O3
                            -report
                            -DBOARD_SUPPORT_BOARD=XK_ETH_XU316_DUAL_100M
                            ${PHY_FLAGS})

# In the compiler flags define either XTCP_STACK_UIP or XTCP_STACK_LWIP
# according to which TCP stack is preferred to run the app note
set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON} -DXTCP_STACK_LWIP)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
