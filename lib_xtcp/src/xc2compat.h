// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#ifndef _xc2compat_h_
#define _xc2compat_h_

#ifdef __XC__
#define unsafe unsafe
#else
#define unsafe
#endif

#ifdef __XC__
#define alias alias
#else
#define alias
#endif

#endif
