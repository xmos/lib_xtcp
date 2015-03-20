// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef _xtcp_impl_h_
#define _xtcp_impl_h_

#if UIP_CONF_IPV6
#define XTCP_IPADDR_CPY_(dest, src) do { dest[0]  = src[0]; \
                                        dest[1]  = src[1]; \
					dest[2]  = src[2]; \
					dest[3]  = src[3]; \
					dest[4]  = src[4]; \
					dest[5]  = src[5]; \
					dest[6]  = src[6]; \
					dest[7]  = src[7]; \
					dest[8]  = src[8]; \
					dest[9]  = src[9]; \
					dest[10] = src[10]; \
					dest[11] = src[11]; \
					dest[12] = src[12]; \
					dest[13] = src[13]; \
					dest[14] = src[14]; \
					dest[15] = src[15]; \
                                      } while (0)

#define XTCP_IPADDR_CMP_(a, b) (a[0]  == b[0] && \
                               a[1]  == b[1] && \
                               a[2]  == b[2] && \
                               a[3]  == b[3] && \
                               a[4]  == b[4] && \
                               a[5]  == b[5] && \
                               a[6]  == b[6] && \
                               a[7]  == b[7] && \
                               a[8]  == b[8] && \
                               a[9]  == b[9] && \
                               a[10] == b[10] && \
                               a[11] == b[11] && \
                               a[12] == b[12] && \
                               a[13] == b[13] && \
                               a[14] == b[14] && \
                               a[15] == b[15])
#else
#define XTCP_IPADDR_CPY_(dest, src) do { dest[0] = src[0]; \
                                        dest[1] = src[1]; \
                                        dest[2] = src[2]; \
                                        dest[3] = src[3]; \
                                      } while (0)


#define XTCP_IPADDR_CMP_(a, b) (a[0] == b[0] && \
                               a[1] == b[1] && \
                               a[2] == b[2] && \
                               a[3] == b[3])
#endif

#endif // _xtcp_impl_h_
