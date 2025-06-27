cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(lib_xtcp_tests)

add_subdirectory(xtcp_bombard_lwip)
add_subdirectory(xtcp_bombard_uip)
