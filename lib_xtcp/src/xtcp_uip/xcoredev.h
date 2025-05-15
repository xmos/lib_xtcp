// Copyright (c) 2011-2016, XMOS Ltd, All rights reserved

#ifndef __XCOREDEV_H__
#define __XCOREDEV_H__

#include <xccompat.h>

enum xcoredev_eth_e {
    XCORE_ETH_NONE,
    XCORE_ETH_MII,
    XCORE_ETH_TX,
};

void xcoredev_init(chanend mac_rx, chanend mac_tx);
unsigned int xcoredev_read(chanend mac_rx, int n);
void xcoredev_send();

#endif /* __XCOREDEV_H__ */
