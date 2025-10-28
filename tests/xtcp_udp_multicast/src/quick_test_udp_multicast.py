#!/usr/bin/python
# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import argparse
import socket
import struct


MCAST_IF_IP = '192.168.200.99'
MCAST_GRP = '224.1.2.3'
MCAST_PORT = 15577
MULTICAST_TTL = 2

# This simple script sends a UDP packet to port 15577 at the
# IP address given for the multicast group, then listens for a response
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(5)

    print("Connecting... to multicast group " + MCAST_GRP + " on interface " + MCAST_IF_IP)
    try:
        sock.bind(('', MCAST_PORT))
        print(f"Listening on port {MCAST_PORT}")

        # Transmitter socket configuration for multicast
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, MULTICAST_TTL)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(MCAST_IF_IP))

        send_msg = "XMOS multicast test message :SOMX"
        print("Sending message: " + send_msg)
        sock.sendto(send_msg.encode('utf-8'), (MCAST_GRP, MCAST_PORT))

        # Receiver socket configuration for multicast
        # This must be done after transmit otherwise it receives its own output
        mreq = struct.pack('4s4s', socket.inet_aton(MCAST_GRP), socket.inet_aton(MCAST_IF_IP))
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

        chunk, addr = sock.recvfrom(1500)
        print("Recv'd message: \"" + chunk.decode('utf-8') + "\" from " + str(addr))

    except socket.timeout:
        print("No response received within the timeout period.")

print("Closed")
