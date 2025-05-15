set(LIB_NAME                lib_xtcp)

set(LIB_VERSION             7.1.0) # Should this be 6.1 or 7.1 or 8? 7.0.0 is also used on Jakes branch

set(LIB_INCLUDES            api
                            src
                            src/xtcp_lwip/include
                            src/xtcp_lwip/xcore/include)
             
set(LIB_DEPENDENT_MODULES   "lib_ethernet(4.0.0)"
                            "lib_logging(3.3.1)"
                            "lib_xassert(4.3.1)"
                            "lib_random(1.0.0)"
                            "lib_otpinfo(2.0.0)")

set(LIB_COMPILER_FLAGS      -g
                            -O3
                            -mno-dual-issue)

XMOS_REGISTER_MODULE()
