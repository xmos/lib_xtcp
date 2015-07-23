// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef __xtcp_conf_derived_h__
#define __xtcp_conf_derived_h__

#ifdef __xtcp_conf_h_exists__
#include "xtcp_conf.h"
#endif

#ifdef __xtcp_client_conf_h_exists__
#include "xtcp_client_conf.h"
#endif

#ifndef XTCP_STRIP_VLAN_TAGS
#define XTCP_STRIP_VLAN_TAGS 0
#endif

#ifndef XTCP_SEPARATE_MAC // Deprecated
#define XTCP_SEPARATE_MAC 0
#endif

#ifndef XTCP_ENABLE_PUSH_FLAG_NOTIFICATION
#define XTCP_ENABLE_PUSH_FLAG_NOTIFICATION 0
#endif

#endif // __xtcp_conf_derived_h__
