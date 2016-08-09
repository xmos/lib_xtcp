// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved

#ifndef PACKETBUF_D_H_
#define PACKETBUF_D_H_

#include <stdint.h>
#include <xccompat.h>
#include "net/rime/rimeaddr.h"

enum{
    PACKETBUF_D_ADDR_SENDER,
};

int               packetbuf_d_set_addr(uint8_t type, NULLABLE_ARRAY_OF(const rimeaddr_t, addr));
#if !__XC__
const rimeaddr_t *packetbuf_d_addr(uint8_t type);
#endif /* __XC__ */
#endif /* PACKETBUF_D_H_ */
