# This file provides overrides to the Doxyfile configuration

PROJECT_NAME           = lib_xtcp
PROJECT_BRIEF          = "TCP/IP library"

INPUT                  = ../lib_xtcp/api

PREDEFINED             = C_API= EXTERN_C= UNSAFE= __DOXYGEN__=1
PREDEFINED += CONST_NULLABLE_ARRAY_OF_SIZE(type,name,size)="const type *name"

