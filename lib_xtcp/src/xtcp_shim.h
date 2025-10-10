// Copyright 2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XTCP_SHIM_H
#define XTCP_SHIM_H

#ifdef __XC__
void client_init_notification(static const unsigned n_xtcp_init, server xtcp_if i_xtcp_init[n_xtcp_init]);
#endif

#endif /* XTCP_SHIM_H */
