cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)

project(lib_xtcp_tests)

add_subdirectory(xtcp_bombard_lwip)
add_subdirectory(xtcp_burst)
add_subdirectory(xtcp_tcp_connect)
add_subdirectory(xtcp_udp_connect)
add_subdirectory(xtcp_xk_evk_xe216_basic)
add_subdirectory(xtcp_xk_eth_316_dual_basic)
