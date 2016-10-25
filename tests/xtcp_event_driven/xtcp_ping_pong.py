#!/usr/bin/env python
import socket
import random
import string
import time
import argparse
import sys
import os
import xmostest
import struct
from multiprocessing import Pool

def print_errors(failure_list):
    # Flatten list
    failure_list = [item for sublist in failure_list for item in sublist]

    if len(failure_list) > 0:
        print '    \ttype\tid\ttime\tlocal\tremote\tsent_l\t?ret_l\t?err\t?mess\t?recv'
        print ''.join(failure_list)

    print 'Lost_packets: {} of {}'.format(len(failure_list), 
                                          args.packets * args.remote_processes * args.remote_ports)

def format_message(message, width):
    return '\n  '.join([message[i:i+width] for i in range(0, len(message), width)])

# Limit reconnect attempts
def attempt_connect(failures, process_port, sock=None):
    for _ in range(3):
        try:
            sock = socket.socket(socket.AF_INET, args.protocol)
            sock.settimeout(1) # seconds
            sock.connect((args.ip, process_port))
            return (failures, sock)

        except socket.error as err:
            failures.append('ERROR\tconn' +
                            '\t{}'.format(process_port - 15533) +
                            '\t_{0:.2f}'.format(time.time() - args.start_time) + # Time
                            '\t{}'.format(sock.getsockname()[1]) + # Local port
                            '\t{}'.format(process_port) + # Remote port
                            '\t' +
                            '\t' +
                            '\t{}\n'.format(err)
                            )

    return (failures, None)

def process_test(process_port):
    # Each thread now has a different seed
    random.seed(args.seed_base + process_port)
    tests_to_perform = args.packets
    failures = []

    (failures, sock) = attempt_connect(failures, process_port)
    if sock is None:
        return failures

    # Once connected, send packets continuously and 
    # match against rebounded packet
    while tests_to_perform:
        time.sleep(args.delay_between_packets)
        length_of_message = random.randint(1, packet_size_limit)
        # Don't allow an 'a' char to be sent, as this kills the remote device
        message = ''.join( [random.choice(string.lowercase[1:]) for c in xrange(length_of_message)] )
        # message = 'bbccdd'

        try:
            sock.send(message)
            returned_message = sock.recv(1460)
            # if returned_message != message:
            if returned_message != message[::-1]: # Reverse string
                failures.append('FAIL\tmiss' +
                                '\t{}'.format(process_port - 15533) +
                                '\t_{0:.2f}'.format(time.time() - args.start_time) + # Time
                                '\t{}'.format(sock.getsockname()[1]) + # Local port
                                '\t{}'.format(process_port) + # Remote port
                                '\t{}'.format(length_of_message) + # Packet length
                                '\t{}'.format(len(returned_message)) +
                                '\t' +
                                '\t{}'.format(message) + 
                                '\t{}\n'.format(returned_message)
                                )

        except socket.timeout as err:
            failures.append('FAIL\ttime' +
                            '\t{}'.format(process_port - 15533) +
                            '\t_{0:.2f}'.format(time.time() - args.start_time) + # Time
                            '\t{}'.format(sock.getsockname()[1]) + # Local port
                            '\t{}'.format(process_port) + # Remote port
                            '\t{}\n'.format(length_of_message) # Packet length
                            )

        except socket.error as err:
            failures.append('FAIL\terr ' +
                            '\t{}'.format(process_port - 15533) +
                            '\t{0:.2f}'.format(time.time() - args.start_time) + # Time
                            '\t{}'.format(sock.getsockname()[1]) + # Local port
                            '\t{}'.format(process_port) + # Remote port
                            '\t{}'.format(length_of_message) + # Packet length
                            '\t' +
                            '\t{}\n'.format(err)
                            )

            # Reconnect
            (failures, sock) = attempt_connect(failures, process_port, sock)
            if sock is None:
                break

        tests_to_perform -= 1
    
    if sock is not None:
        sock.shutdown(socket.SHUT_RDWR)
        sock.close()

    return failures

# Remote device is setup to exit() if the first character of a message is 'a'
def kill_remote_device():
    try:
        sock = socket.socket(socket.AF_INET, args.protocol)
        sock.settimeout(10) # seconds
        sock.connect((args.ip, args.start_port))
        sock.send('a')
        sock.close()

    except socket.error as err:
        # Do nothing and wait for remote device to timeout
        print 'ERROR: Could not kill remote device'

def reflect_test():
    # Each process handles one remote port 
    pool = Pool(args.remote_processes * args.remote_ports)

    # Each process on the xC device has a pool of ports it can
    # read from, with each pool spaced 10 apart
    port_pool = [ j + (10*i) for i in range(0, args.remote_processes) for j in range(args.start_port, args.start_port + args.remote_ports)]
    # port_pool = [15533, 15533, 15533, 15533]
    # .get(9999999) is added to avoid this bug: https://bugs.python.org/issue8296
    pool.map_async(process_test, port_pool, 1, callback=print_errors).get(9999999)

    pool.close()
    pool.join()
    pool.terminate()

def connect_test():
    tests_to_perform = args.packets
    
    try:
        sock = socket.socket(socket.AF_INET, args.protocol)
        sock.bind(('', 15533))
        sock.listen(5)
        conn, addr = sock.accept()
        # if(addr[1] != args.start_port):
            # print 'ERROR: Bound to wrong address'

        while tests_to_perform:
            message = conn.recv(1460)
            if message:
                conn.sendall(message)
            tests_to_perform -= 1

        sock.close()
    
    except socket.error as err:
        print 'ERROR: Could not connect to device'

def multicast_test():
    MCAST_GRP = '224.1.1.1'
    MCAST_PORT = 5007

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((MCAST_GRP, MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)

    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton('192.168.2.1'))

    while True:
      print sock.recv(10240)

    # MCAST_GRP = '224.1.1.1'
    # MCAST_PORT = 5007

    # sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    # sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    # sock.bind((MCAST_GRP, MCAST_PORT))
    # mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    # sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    # while True:
    #   print sock.recv(10240)

    # import socket

    # MCAST_GRP = '224.1.1.1'
    # MCAST_PORT = 5007

    # sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    # sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton('192.168.2.1'))
    # sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    # while 1:
    #     sock.sendto("bcdef", (MCAST_GRP, MCAST_PORT))

def udp_bind_test():
    print "UDP BIND"
    tests_to_perform = args.packets
    
    try:
        # Test only performed for UDP
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('', args.local_port))
        # sock.listen(5)
        # conn, addr = sock.accept()
        # if(addr[1] != args.start_port):
        #     print 'ERROR: Bound to wrong address'

        while tests_to_perform:
            message, addr = sock.recvfrom(1460)
            if(addr[1] != args.start_port):
                print 'ERROR: Bound to wrong port'
            if message:
                sock.sendto(message, addr)
            tests_to_perform -= 1

        sock.close()
    
    except socket.error as err:
        print err
        print 'ERROR: Could not connect to device'

def check_and_set_args():
    if args.protocol == 'UDP':
        args.protocol = socket.SOCK_DGRAM
    else:
        args.protocol = socket.SOCK_STREAM

    if args.ip is None:
         parser.error('Need IP address')

    if args.start_port is None:
        parser.error('Need starting port')

    if args.packet_size_limit > 1460:
        parser.error('Packet size is too large and will be split')

    args.start_time = time.time()

    # Use the current git hash to seed the random number generator,
    # to avoid the number of test cases for a particular snapshot increasing
    # each time the view is built in the CI system.
    script_location = os.path.dirname(os.path.realpath(__file__))
    stdout, stderr = xmostest.call_get_output(['git', 'rev-parse', 'HEAD'],
                                              cwd=script_location)

    args.seed_base = int(stdout[0].strip(), 16) # Git hash is hexadecimal string

if __name__ == '__main__':
    # Defaults
    packets = 100000
    packet_size_limit = 50
    delay_between_packets = 0
    remote_processes = 2
    remote_ports = 2
    local_port_udp = 15999
    protocol = "UDP"

    parser = argparse.ArgumentParser(description='TCP/UDP tester')
    # Non-default arguments
    parser.add_argument('--ip', type=str, 
      help="IP address")
    parser.add_argument('--start-port', type=int,
      help="TCP/IP port")
    # Default arguments
    parser.add_argument('--local-port', default=local_port_udp, type=int,
      help="Local port for UDP bind test (default='%s')" % local_port_udp)
    parser.add_argument('--remote-processes', default=remote_processes, type=int,
      help="Remote processes to connect to (default='%s')" % remote_processes)
    parser.add_argument('--remote-ports', default=remote_ports, type=int,
      help="Remote ports to connect to (default='%s')" % remote_ports)
    parser.add_argument('--protocol', default=protocol, type=str,
      help="TCP/UDP protocol (default='%s')" % protocol)
    parser.add_argument('--packets', default=packets, type=int,
      help="Number of packets to send (defaults='%s')" % packets)
    parser.add_argument('--packet-size-limit', default=packet_size_limit, type=int,
      help="Size of packets to send (defaults='%s')" % packet_size_limit)
    parser.add_argument('--delay-between-packets', default=delay_between_packets, type=float,
      help="Delay between packets (defaults='%s')" % delay_between_packets)
    args = parser.parse_args()

    check_and_set_args()
    reflect_test()
    # connect_test()
    # udp_bind_test()
    # multicast_test()
    print "Time taken: " + str(time.time() - args.start_time)
    kill_remote_device()