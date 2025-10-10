// Copyright 2015-2025 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef _XC2COMPAT_H_
#define _XC2COMPAT_H_

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

#ifndef NULLABLE_CLIENT_INTERFACE
#ifdef __XC__
#define NULLABLE_CLIENT_INTERFACE(type, name) client interface type ?name
#else
#define NULLABLE_CLIENT_INTERFACE(type, name) unsigned name
#endif
#endif

#ifndef SERVER_INTERFACE_ARRAY
#ifdef __XC__
#define SERVER_INTERFACE_ARRAY(type, name, size) server interface type name[size]
#else
#define SERVER_INTERFACE_ARRAY(type, name, size) unsigned *name
#endif
#endif

#ifndef CONST_NULLABLE_ARRAY_OF_SIZE
#ifdef __XC__
#define CONST_NULLABLE_ARRAY_OF_SIZE(type, name, size) const type (&?name)[size]
#else
#define CONST_NULLABLE_ARRAY_OF_SIZE(type, name, size) const type *name
#endif
#endif

#ifndef static_const_unsigned
#ifdef __XC__
#define static_const_unsigned static const unsigned
#else
#define static_const_unsigned const unsigned
#endif
#endif

#endif /* _XC2COMPAT_H_ */
