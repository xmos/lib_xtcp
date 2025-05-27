set(LIB_NAME                lib_xtcp)

set(LIB_VERSION             6.1.0)

set(LIB_INCLUDES            api
                            src
                            src/xtcp_lwip/include
                            src/xtcp_lwip/xcore/include)
             
set(LIB_DEPENDENT_MODULES   "lib_ethernet(4.0.1)"
                            "lib_logging(3.3.1)"
                            "lib_xassert(4.3.1)"
                            "lib_random(1.2.0)"
                            "lib_otpinfo(2.2.1)")

set(LIB_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue)

set(LIB_OPTIONAL_HEADERS    xtcp_client_conf.h xtcp_conf.h)

XMOS_REGISTER_MODULE()
