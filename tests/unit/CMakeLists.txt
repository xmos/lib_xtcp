
cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(unit_test)

set(APP_HW_TARGET           xk-eth-316-dual.xn)
set(XMOS_SANDBOX_DIR        ${CMAKE_SOURCE_DIR}/../../..)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)
list(APPEND APP_DEPENDENT_MODULES lib_unity)

set(APP_XSCOPE_SRCS         config.xscope)

# LwIP options needed for library build
set(LWIP_OPTS_PATH          "lwip/contrib/ports/xmos/lib/standard")

set(APP_COMPILER_FLAGS      -O3
                            -g
                            -nno-dual-issue
                            -report
                            -Wall
                            -DDEBUG_PRINT_ENABLE=1
                            -DDEBUG_PRINT_ENABLE_LIB_XTCP=1
                            -DBOARD_SUPPORT_BOARD=XK_ETH_316_DUAL)

# test sources
file(GLOB_RECURSE APP_C_SRCS RELATIVE ${CMAKE_CURRENT_LIST_DIR} "test_*/src/*.c")

set(APP_INCLUDES            include)

# Create config for each test
file(GLOB_RECURSE tests RELATIVE ${CMAKE_CURRENT_LIST_DIR} "test_*/src/test*.c")
foreach(test_file ${tests})
    get_filename_component(test_name ${test_file} NAME_WE)
    set(SOURCE_FILES_${test_name} ${test_file})
endforeach()

# Enable auto gen of test runners
set(LIB_UNITY_AUTO_TEST_RUNNER ON)

# Disable unity features that we dont use
set(LIB_UNITY_USE_FIXTURE OFF)
set(LIB_UNITY_USE_MEMORY OFF)

XMOS_REGISTER_APP()
