# This exists to test the Makefile build of lib_xtcp
# Target must be 200-explorer because of lib_otp 2/3 version issues with xmake

TARGET = XCORE-200-EXPLORER

APP_NAME =

COMMON_FLAGS   = -O1 -g -report -DBOARD_SUPPORT_BOARD=XK_EVK_XE216 ../config.xscope

XCC_FLAGS_200_EXP_LWIP  = $(COMMON_FLAGS) -DXTCP_STACK_LWIP
XCC_FLAGS_200_EXP_UIP  	= $(COMMON_FLAGS) -DXTCP_STACK_UIP

USED_MODULES = lib_xtcp lib_board_support

#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
