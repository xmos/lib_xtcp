#!/usr/bin/python

import argparse
import socket
import sys


parser = argparse.ArgumentParser(description='TCP tester')
parser.add_argument('ip', type=str, help="IP address")
args = parser.parse_args()

# This simple script sends a UDP packet to port 15533 at the
# IP address given as the first argument to the script
# This is to test the simple UDP example XC program
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

print ("Connecting..")
sock.connect((args.ip, 15533))
print ("Connected")

msg = "hello world"
print ("Sending message: " + msg)
sock.send(bytes(msg, "ascii"))

print ("Closing...")
sock.close()
print ("Closed")
