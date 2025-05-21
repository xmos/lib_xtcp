cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_simple_webserver)

set(APP_HW_TARGET           XCORE-200-EXPLORER)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE          ON)

set(COMPILER_FLAGS_COMMON   -g
                            -O3
                            -report
                            -DDEBUG_PRINT_ENABLE
                            -DRGMII=1
                            -DBOARD_SUPPORT_BOARD=XK_EVK_XE216)

# In the compiler flags define either XTCP_STACK_UIP or XTCP_STACK_LWIP
# according to which TCP stack is preferred to run the app note
set(APP_COMPILER_FLAGS      ${COMPILER_FLAGS_COMMON} -DXTCP_STACK_LWIP)

set(APP_XSCOPE_SRCS         src/config.xscope)

set(XMOS_SANDBOX_DIR        ${CMAKE_CURRENT_LIST_DIR}/../../..)

XMOS_REGISTER_APP()
