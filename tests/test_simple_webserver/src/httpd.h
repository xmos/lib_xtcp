// Copyright (c) 2016, XMOS Ltd, All rights reserved

#ifndef _httpd_h_
#define _httpd_h_

#include "xtcp.h"

void httpd_init(chanend tcp_svr);
void httpd_handle_event(chanend tcp_svr, REFERENCE_PARAM(xtcp_connection_t, conn));

#endif // _httpd_h_

