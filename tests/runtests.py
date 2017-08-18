#!/usr/bin/env python2.7
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
