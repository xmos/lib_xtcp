#!/usr/bin/env python
# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
import xmostest

if __name__ == "__main__":
    xmostest.init()

    xmostest.register_group("lib_xtcp",
                            "slicekit_configuration_tests",
                            "Slickit configuration tests",
    """
Test different configurations of a sliceKIT-200 communicating with a PC using
a simple ping-pong test.
    """
    )

    xmostest.register_group("lib_xtcp",
                            "micarray_configuration_tests",
                            "Micarray configuration tests",
    """
Test different configurations of an Array Microphone communicating with a PC using
a simple ping-pong test.
    """
    )

    xmostest.register_group("lib_xtcp",
                            "explorer_configuration_tests",
                            "Explorer kit configuration tests",
    """
Test different configurations of a explorerKIT-200 communicating with a PC using
a simple ping-pong test.
    """
    )

    xmostest.runtests()

    xmostest.finish()
