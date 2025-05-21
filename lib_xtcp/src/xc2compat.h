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

#ifdef __XC__
#define NULLABLE_CLIENT_INTERFACE_TYPE(type, name) client interface type ?name
#else
#define NULLABLE_CLIENT_INTERFACE_TYPE(type, name) unsigned name
#endif

#ifdef __XC__
#define SERVER_INTERFACE_ARRAY(type, name, size) server interface type name[size]
#else
#define SERVER_INTERFACE_ARRAY(type, name, size) unsigned *name
#endif

#ifdef __XC__
#define CONST_NULLABLE_ARRAY_OF_SIZE(type, name, size) const type (&?name)[size]
#else
#define CONST_NULLABLE_ARRAY_OF_SIZE(type, name, size) const type *name
#endif

#ifdef __XC__
#define CLEARS_NOTIFICATION [[clears_notification]]
#else
#define CLEARS_NOTIFICATION
#endif

#ifdef __XC__
#define NOTIFICATION [[notification]] slave 
#else
#define NOTIFICATION
#endif

#ifdef __XC__
#define static_const_unsigned static const unsigned
#else
#define static_const_unsigned const unsigned
#endif

#endif /* _xc2compat_h_ */
