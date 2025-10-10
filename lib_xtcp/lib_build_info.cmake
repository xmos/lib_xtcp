set(LIB_NAME                lib_xtcp)

set(LIB_VERSION             6.2.0)

# Please note: LWIP_OPTS_PATH must be set in the application's CMakeLists.txt file
if(NOT DEFINED LWIP_OPTS_PATH)
    message(FATAL_ERROR "LWIP_OPTS_PATH must be defined in the application's CMakeLists.txt file")
endif()

# LWIP
set(LWIP_DIR                ${XMOS_SANDBOX_DIR}lib_xtcp/lib_xtcp/lwip)
set(LWIP_CONTRIB_DIR        ${LWIP_DIR}/contrib)

include("${XMOS_SANDBOX_DIR}/lib_xtcp/lib_xtcp/lwip/src/Filelists.cmake")
include("${XMOS_SANDBOX_DIR}/lib_xtcp/lib_xtcp/lwip/contrib/Filelists.cmake")
include("${XMOS_SANDBOX_DIR}/lib_xtcp/lib_xtcp/lwip/contrib/ports/xmos/Filelists.cmake")

# Map LwIP source files to relative paths for module build
set(MODULE_DIR              ${XMOS_SANDBOX_DIR}lib_xtcp/lib_xtcp/)

if (LWIP_VERSION_STRING)
    message(STATUS "Capturing LwIP")
    message(STATUS "LwIP version: ${LWIP_VERSION_STRING}")
    set(XTCP_LWIP_VERSION_STRING ${LWIP_VERSION_STRING} CACHE STRING "")

    # TODO - future addition ${lwipmbedtls_SRCS}
    # ${lwipallapps_SRCS} - Optional apps
    # ${lwipcontribexamples_SRCS} - Optional examples
    # ${lwipcontribapps_SRCS} - Optional contrib apps

    # Map source files to xcommon.cmake relative paths
    foreach(lwip_file ${lwipnoapps_SRCS} ${lwipcontribportxmos_SRCS})
        string(REGEX REPLACE "${MODULE_DIR}" "" REL_SRC_PATH "${lwip_file}")
        list(APPEND LWIP_CODE_LIST ${REL_SRC_PATH})
    endforeach()

    set(XTCP_LWIP_CODE_LIST ${LWIP_CODE_LIST} CACHE STRING "")

else()
    message(STATUS "Reporting LwIP")
    message(STATUS "xtcp LwIP version: ${XTCP_LWIP_VERSION_STRING}")

endif()

# lib_xtcp
set(LIB_C_SRCS              src/client_queue.c
                            src/connection.c
                            src/lwip_shim.c
                            src/pbuf_shim.c
                            src/tcp_transport.c
                            src/udp_recv.c
                            src/dns_found.c
                            ${XTCP_LWIP_CODE_LIST})

set(LIB_XC_SRCS             src/xtcp_lwip.xc
                            src/xtcp_shim.xc)

set(LIB_INCLUDES            api
                            src
                            "lwip/src/include"
                            "lwip/contrib"
                            "lwip/contrib/ports/xmos/include"
                            "${LWIP_OPTS_PATH}")

set(LIB_DEPENDENT_MODULES   "lib_ethernet(4.1.0)"
                            "lib_logging(3.4.0)"
                            "lib_xassert(4.3.2)"
                            "lib_random(1.3.0)"
                            "lib_otpinfo(2.2.1)")

set(LIB_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue
                            -Wall
                            -Wextra
                            -Wconversion
                            -Wdiv-by-zero
                            -Wfloat-equal
                            -Wsign-compare
                            -DSSIZE_MAX=2147483647)

set(LIB_OPTIONAL_HEADERS    xtcp_client_conf.h xtcp_conf.h)

XMOS_REGISTER_MODULE()
