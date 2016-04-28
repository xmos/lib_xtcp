// Copyright (c) 2016, XMOS Ltd, All rights reserved

#include <string.h>
#include "net/packetbuf_d.h"

static rimeaddr_t packetbuf_d_addr_sender;

int packetbuf_d_set_addr(uint8_t type, const rimeaddr_t *addr){

    switch(type){
    case PACKETBUF_D_ADDR_SENDER:
        memcpy(&packetbuf_d_addr_sender, addr, sizeof(rimeaddr_t));
        return 1;
        break;

    default:
        return 0;
        break;
    }

}

/*----------------------------------------------------------------------------*/
const rimeaddr_t *packetbuf_d_addr(uint8_t type){
    if(type == PACKETBUF_D_ADDR_SENDER){
        return &packetbuf_d_addr_sender;
    } else {
        return NULL;
    }
}
