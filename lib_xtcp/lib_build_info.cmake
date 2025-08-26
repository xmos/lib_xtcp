set(LIB_NAME                lib_xtcp)

set(LIB_VERSION             6.2.0)

set(LIB_INCLUDES            api
                            src
                            src/xtcp_lwip/include
                            src/xtcp_lwip/xcore/include)
             
set(LIB_DEPENDENT_MODULES   "lib_ethernet(develop)" # Planning for 4.1.0
                            "lib_logging(3.4.0)"
                            "lib_xassert(4.3.2)"
                            "lib_random(1.3.0)"
                            "lib_otpinfo(2.2.1)")

set(LIB_COMPILER_FLAGS      -g
                            -O3)

set(LIB_OPTIONAL_HEADERS    xtcp_client_conf.h xtcp_conf.h)

XMOS_REGISTER_MODULE()
