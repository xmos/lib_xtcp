#!/usr/bin/python
# Copyright 2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import argparse
import socket


parser = argparse.ArgumentParser(description='TCP tester')
parser.add_argument('ip', type=str, help="IP address")
args = parser.parse_args()

# This simple script sends a TCP packet to port 15534 at the
# IP address given as the first argument to the script
# This is to test the simple TCP example XC program
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:

    sock.settimeout(5)

    print("Connecting..")
    try:
        sock.connect((args.ip, 15534))
        print("Connected")

        msg = "hello, world"
        print("Sending message: " + msg)
        sock.send(bytes(msg, "ascii"))

        chunk = sock.recv(20)
        print("Recv'd message: " + str(chunk))

    except socket.timeout:
        print("No response received within the timeout period.")

print("Closed")
