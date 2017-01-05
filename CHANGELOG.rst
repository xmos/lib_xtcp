TCP/IP library change log
=========================

6.0.0
-----

  * CHANGE: Unified the branches of uIP and lwIP as the backend of the XTCP
    stack. The default is uIP. To change the stack, define XTCP_STACK in your
    makefile to be either UIP or LWIP. Then, instead of calling xtcp(...), call
    either xtcp_uip(...) or xtcp_lwip(...) respectively.
  * CHANGE: The interface between the client and server is now event-driven
    rather than polling.
  * CHANGE: Channels have been replaced by interfaces as communication medium
    between client and server.
  * REMOVED: The following xtcp_event_types: XTCP_PUSH_DATA, XTCP_REQUEST_DATA,
    XTCP_POLL, XTCP_ALREADY_HANDLED
  * CHANGE: The fields of packet_length and client_num have been added to the
    xtcp_connection_t structure.
  * REMOVED: xtcp_connection_t no longer has a xtcp_connection_type_t field.
  * REMOVED: The ability to pause a connection
  * REMOVED: The ability to partially acknowledge a packet
  * REMOVED: Support for IPv6
  * REMOVED: the ability to send with an index. This functionality is easily
    replicated with a call to send() with the pointer of the array index
    location, i.e. &(data[index]).
  * REMOVED: Support for XTCP_EXCLUDE_* macros which reduced functionality in
    order to save code size
  * FIXED: Problem where ethernet packets smaller than 64 bytes would be incorrectly padded with uIP.

5.1.0
-----

  * ADDED: Support for using lib_wifi to provide the physical transport

5.0.0
-----

  * ADDED: Port of LwIP TCP/IP stack

  * Changes to dependencies:

    - lib_crypto: Added dependency 1.0.0

4.0.3
-----

  * ADDED: Support to enable link status notifications

4.0.2
-----

  * CHANGE: uIP timer.h renamed to uip_timer.h to avoid conflict with xcore
    timer.h
  * CHANGE: Update to source code license and copyright

4.0.1
-----

  * CHANGE: MAC address parameter to xtcp() is now qualified as const to allow
    parallel usage
  * RESOLVED: Fixed issue with link up/down events being ignored when SMI is not
    polled within XTCP

4.0.0
-----

  * CHANGE: Moved over to new file structure
  * CHANGE: Updated to use new lib_ethernet

  * Changes to dependencies:

    - lib_ethernet: Added dependency 3.0.0

    - lib_gpio: Added dependency 1.0.0

    - lib_locks: Added dependency 2.0.0

    - lib_logging: Added dependency 2.0.0

    - lib_otpinfo: Added dependency 2.0.0

    - lib_xassert: Added dependency 2.0.0


Legacy release history
----------------------

3.2.1
-----

  * Changes to dependencies:

    - sc_ethernet: 2.2.7rc1 -> 2.3.1rc0

      + Fix invalid inter-frame gaps.
      + Adds AVB-DC support to sc_ethernet

3.2.0
-----
  * Added IPv6 support

3.1.5
-----
  * Fixed channel protocol bug that caused crash when xCONNECT is
    heavily loaded
  * Various documentation updates
  * Fixes to avoid warning in xTIMEcomposer studio version 13.0.0
    or later

  * Changes to dependencies:

    - sc_ethernet: 2.2.5rc2 -> 2.2.7rc1

      + Fix buffering bug on full implementation that caused crash under
      + Various documentation updates

3.1.4
-----
  * Updated ethernet dependency to version 2.2.5

3.1.3
-----
  * Updated ethernet dependency to version 2.2.4
  * Fixed corner case errors/improved robustness in DHCP protocol handling

3.1.2
-----
  * Fixed auto-ip bug for 2-core xtcp server

3.1.1
-----
  * Minor code demo app fixes (port structures should be declared on
    specific tiles)

3.1.0
-----
  * Compatible with 2.2 module_ethernet
  * Updated to new intializer api and integrated ethernet server

3.0.1
-----

   * Updated to use latest sc_ethernet package

3.0.0
-----
   * Fixed bugs in DHCP and multicast UDP
   * Updated packaging, makefiles and documentation
   * Updated to use latest sc_ethernet package

2.0.1
-----

   * Further memory improvements
   * Additional conditional compilation
   * Fix to zeroconf with netbios option enabled

2.0.0
-----

   * Memory improvements
   * Fix error whereby UDP packets with broadcast destination were not received
   * An initial implementation of a TFTP server

1.3.1
-----

   * Initial implementation

