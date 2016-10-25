#!/usr/bin/python	
import struct
import socket
import time
import os, commands
import sys

HOST='192.168.0.41'
DEST_PORT=49468
SRC_PORT=49454
SRC_PORT2=49455
SRC_PORT3=49456

def socket_send_d(address, s, length, data):
	print "Sending",len(data),"bytes"
	s.sendto(data, address)	

def socket_recv_d(s, length, data):
	while (len(data) < length):
		string, address = s.recvfrom(length)
		data += string
	print "Received",len(data),"bytes from ",address
	return data, address

def socket_send(s, length):
	data=""
	for i in range(0, length):
		data += chr(i % 256)
	print "Sending",len(data),"bytes"
	s.sendall(data)

def socket_recv(s, length):
	data = ""
	while (len(data) < length):
		data += s.recv(length)
	print "Received",len(data),"bytes"
	for i in range(0, length):
		if data[i] != chr(i % 256):
			print "FAILED: Invalid data, got ",data[i]," expected ",chr(i % 256),"at byte ", i
	
def echo_test(protocol):

	data_len = 1024
	i = 0

	time.sleep(1)
	
	# Client
	while data_len:
		s = socket.socket(socket.AF_INET, protocol)
		s.settimeout(10.0)
		i = i + 1
		print DEST_PORT + i
		s.connect((HOST, DEST_PORT + i))
		socket_send(s, data_len)
		socket_recv(s, data_len)
		s.close()
		time.sleep(0.2)
		data_len = data_len / 2

	data_len = 1024
	i = 0
		
	# Server
	while data_len:
		data = ""
		s = socket.socket(socket.AF_INET, protocol)
		s.settimeout(10.0)
		i = i + 1
		print "Listening on port ",SRC_PORT + i
		s.bind(('', SRC_PORT + i))
		
		if (protocol == socket.SOCK_STREAM):
			s.listen(1)
			s, address = s.accept()
			s.settimeout(10.0)
			data, tmp = socket_recv_d(s, data_len, data)
		else:
			data, address = socket_recv_d(s, data_len, data)
			
		socket_send_d(address, s, data_len, data)
		
		if (protocol == socket.SOCK_STREAM):
			s.shutdown(2)
			
		s.close()
		data_len = data_len / 2


def echo_test2(protocol):

	len = 1024
	i = 100
			
	# Server
	data = ""
	s = socket.socket(socket.AF_INET, protocol)
	
	if (host2):
		i = i + 1
	else:
		s.settimeout(10.0)		
		
	print "Listening on port ",SRC_PORT + i
	s.bind(('', SRC_PORT + i))	
	s.listen(1)
	s, address = s.accept()
	s.settimeout(10.0)
	data, tmp = socket_recv_d(s, len, data)
	time.sleep(2)
	socket_send_d(address, s, len, data)
	s.shutdown(2)			
	s.close()
	
def speed_test(protocol):
	len = 81920
	data = ""
	s = socket.socket(socket.AF_INET, protocol)
	s.settimeout(10.0)
	print "Listening on port ",SRC_PORT
	s.bind(('', SRC_PORT))
		
	if (protocol == socket.SOCK_STREAM):
		s.listen(1)
		s, address = s.accept()
		s.settimeout(10.0)
		socket_recv(s, len)
	else:
		data, address = socket_recv_d(s, len, data)
			
	if (protocol == socket.SOCK_STREAM):
		s.shutdown(2)
		
	s.close()

def ping_test(addr):
	cmd="ping -c 1 " + addr
	status,output = commands.getstatusoutput(cmd)
	if (status != 0):
		print "FAILED:"

	print output

def runtests():
	global host2
	
	if len(sys.argv) > 1:
		host2 = True
		print "Test machine 2"
	else:
		print "Test machine 1"
	
	if host2 == False:
		echo_test(socket.SOCK_DGRAM)
		echo_test(socket.SOCK_STREAM)
		speed_test(socket.SOCK_STREAM)
		speed_test(socket.SOCK_DGRAM)
		
	echo_test2(socket.SOCK_STREAM)
	
	if host2 == False:
		ping_test(HOST)
	
	print "Done"       
	
host2 = False	
runtests()



