# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import socket
import random
import string
import time
import argparse
import sys
import subprocess
import struct
import urllib.request
import urllib.error
from multiprocessing import Pool
import copy

# This test script can run a webserver test, a reflect test (sending and receiving), a connection test.
#
# Simple webserver test, opens an HTTP connection on port 80 and returns the text supplied by the DUT.
# Typical usage, python xtcp_ping_pong.py --ip 192.168.200.178 --start-port 80 --test webserver
#
# Reflect test sends data to the DUT and expects the same data but bytes reversed in the array to be returned from
# the DUT.
# --start-port should be 15533, defined in tests/common/include/common.h
# --remote-processes and --remote-ports define the number of reflect process run on the DUT, and the number of ports each process handles.
# --protocol TCP or UDP.
# --packets, number of packets to attempt to send.
# --delay-between-packets, in seconds
# --num-timeouts-reconnect is the number of sequential timeouts seen before a reconnection is attempted, for UDP sockets.
# --halt-sequential-errors is the number of sequential issues seen before an error is reported and the test is halted.
#       Must be greater than '--num-timeouts-reconnect'. This may be for timeouts seen on UDP, packets refused by the
#       DUT, or 'misses', where the returned data does not match the sent data.
# Note: for TCP connections, 3 repeated connection timeouts are flagged as an error.
#
# Typical usage,
#   python xtcp_ping_pong.py --ip 192.168.200.198 --start-port 15533 --remote-processes 1 --remote-ports 1 \
#   --protocol TCP --packets 100 --delay-between-packets 0.002 --halt-sequential-errors 11 --num-timeouts-reconnect 3
#
# Connection test runs the reflect test repeatedly with a small number of packets, say 10, so it tests the DUTs
# ability to handle connection/disconnection in the case of TCP, and the ability of the DUT to handle the same host
# with changing host ports for UDP.
# Typical usage,
#   python xtcp_ping_pong.py --test connection --ip 192.168.200.199 --start-port 15533 --remote-processes 1 \
#   --remote-ports 1 --protocol TCP --packets 10 --delay-between-packets 0.002 --halt-sequential-errors 5 --num-timeouts-reconnect 3
#
# This scripts stores issues in the list variables 'failures', these are then printed out at teh end of the test for
# the pytest script running this one to pick up and parse.
#   Issues are reported prefixed with 'Info:', 'LOSS:' or 'ERROR:'.


def print_errors(failure_list):
    # Flatten list
    failure_list = [item for sublist in failure_list for item in sublist]

    if len(failure_list) > 0:
        print('    \ttype\tid\ttime\tlocal\tremote\tsent_l\t?ret_l\t?err\t?mess\t?recv')
        print(''.join(failure_list))

    print('Lost_packets: {} of {}'.format(len(failure_list),
                                          args.packets * args.remote_processes * args.remote_ports))


def build_base_string(short_name, args, socket, length=0):
    error = (
        f'\t{short_name}' +
        f'\t{args.start_port - 15533}' +
        '\t{0:.2f}'.format(time.time() - args.start_time) +
        f'\t{socket.getsockname()[1]}' +
        f'\t{args.start_port}'
    )
    error += '\t'
    if length != 0:
        error += f'{length}'
    return error


def build_basic_report(short_name, args, socket, length=0):
    error = build_base_string(short_name, args, socket, length)
    error += '\n'
    return error


def build_exception_report(short_name, args, socket, err, length=0):
    error = build_base_string(short_name, args, socket, length)
    error += '\t'
    error += f'\t{err}\n'
    return error


def build_message_report(short_name, args, socket, length, message, returned_message):
    error = build_base_string(short_name, args, socket, length)
    error += (
        f'\t{len(returned_message)}' +
        '\t' +
        f'\t{message}' +
        f'\t{returned_message}\n'
    )
    return error


def format_message(message, width):
    return '\n  '.join([message[i:i+width]
                        for i in range(0, len(message), width)])


def attempt_connect(failures, args, sock=None):
    # Limit reconnect attempts
    for _ in range(3):
        try:
            if args.protocol == "UDP":
                sock_proto = socket.SOCK_DGRAM
            else:
                sock_proto = socket.SOCK_STREAM

            sock = socket.socket(socket.AF_INET, sock_proto)
            sock.settimeout(1)  # seconds
            sock.connect((args.ip, args.start_port))
            return (failures, sock)

        except socket.error as err:
            failures.append(
                'Info:' + build_exception_report('conn', args, sock, err)
            )

    # Sequential connect attempts failure
    failures.append(
        'ERROR:' + build_basic_report('conn', args, sock)
    )

    return (failures, None)


def process_test(args):
    # Each thread now has a different seed
    random.seed(args.seed_base + args.start_port)
    tests_to_perform = args.packets
    failures = []

    (failures, sock) = attempt_connect(failures, args)
    if sock is None:
        return failures

    num_timeouts = 0
    num_exceptions = 0

    # Once connected, send packets continuously and
    # match against rebounded packet
    while tests_to_perform:
        tests_to_perform -= 1
        time.sleep(args.delay_between_packets)
        sys.stdout.write('.')  # show progress
        sys.stdout.flush()
        length_of_message = args.packet_size_limit
        # Don't allow an 'a' char to be sent, as this kills the remote device
        message = ''.join(random.choice(
            string.ascii_lowercase[1:]) for c in range(length_of_message))
        # message = 'bbccdd'

        message = message.encode('ascii')

        try:
            sock.send(message)
            # Receive up to one MTU of data
            returned_message = sock.recv(1500)

            # if returned_message != message:
            if returned_message != message[::-1]:  # Reverse string
                failures.append(
                    'LOSS:' + build_message_report('miss', args, sock, length_of_message, message, returned_message)
                )

            # timeout checks, force action to be 'n' sequential timeouts
            num_timeouts = 0
            num_exceptions = 0

        except socket.timeout:
            num_timeouts += 1
            failures.append(
                'LOSS:' + build_basic_report('time', args, sock, length_of_message)
            )

            if args.num_timeouts_reconnect != 0 and num_timeouts >= args.num_timeouts_reconnect:
                # Reconnect
                (failures, sock) = attempt_connect(failures, args, sock)
                if sock is None:
                    break

            if args.halt_sequential_errors != 0 and num_timeouts >= args.halt_sequential_errors:
                failures.append(
                    'ERROR:' + build_basic_report('seq-time', args, sock, length_of_message)
                )
                break

        except socket.error as err:
            num_exceptions += 1
            failures.append(
                'LOSS:' + build_exception_report('err', args, sock, err, length_of_message)
            )

            # Reconnect
            (failures, sock) = attempt_connect(failures, args, sock)
            if sock is None:
                break

            if args.halt_sequential_errors != 0 and num_exceptions >= args.halt_sequential_errors:
                failures.append(
                    'ERROR:' + build_exception_report('seq-err', args, sock, err, length_of_message)
                )
                break

    if tests_to_perform != 0:
        failures.append(
            'Info:' + build_basic_report('runs', args, sock, args.packets - tests_to_perform)
        )

    if sock is not None:
        sock.shutdown(socket.SHUT_RDWR)
        sock.close()

    # If printing progress '.' then add newline
    print('')
    return failures


def kill_remote_device(args):
    # Remote device is setup to exit() if the first character of a message is 'a'
    if args.protocol == "UDP":
        sock_proto = socket.SOCK_DGRAM
    else:
        sock_proto = socket.SOCK_STREAM

    with socket.socket(socket.AF_INET, sock_proto) as sock:
        try:
            sock.settimeout(10)  # seconds
            sock.connect((args.ip, args.start_port))
            sock.send(b'a')

        except socket.error as err:
            # Do nothing and wait for remote device to timeout
            print(f'ERROR: Could not kill remote device: {err}')


def reflect_test(args):
    print(f"{args.protocol} test starting...")

    # # Each process handles one remote port
    pool = Pool(args.remote_processes * args.remote_ports)

    # Each process on the xC device has a pool of ports it can
    # read from, with each pool spaced 10 apart
    port_pool = [
        j + (10 * i) for i in range(0, args.remote_processes)
        for j in range(args.start_port, args.start_port + args.remote_ports)
    ]

    args_pool = []
    for x in port_pool:
        print(x)
        args_copy = copy.deepcopy(args)
        args_copy.start_port = x
        args_pool.append(args_copy)

    pool.map_async(process_test, args_pool, 1, callback=print_errors)

    pool.close()
    pool.join()
    pool.terminate()


def connect_test(args):
    tests_to_perform = args.packets

    while tests_to_perform:
        print(f"test {tests_to_perform}")
        tests_to_perform -= 1

        failures = reflect_test(args)
        if failures is not None:
            print_errors(failures)

        if tests_to_perform:
            time.sleep(3)


def multicast_test():
    MCAST_GRP = '224.1.1.1'
    MCAST_PORT = 5007

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((MCAST_GRP, MCAST_PORT))
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)

    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF,
                    socket.inet_aton('192.168.2.1'))

    while True:
        print(sock.recv(10240))


def udp_bind_test():
    print("UDP BIND")
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
            if (addr[1] != args.start_port):
                print('ERROR: Bound to wrong port')
            if message:
                sock.sendto(message, addr)
            tests_to_perform -= 1

        sock.close()

    except socket.error as err:
        print(err)
        print('ERROR: Could not connect to device')


def check_and_set_args(args):
    if args.ip is None:
        parser.error('Need IP address')

    if args.start_port is None:
        parser.error('Need starting port')

    if args.packet_size_limit > 1460:
        parser.error('Packet size is too large and will be split')

    if args.num_timeouts_reconnect != 0 and args.halt_sequential_errors != 0:
        if args.num_timeouts_reconnect > args.halt_sequential_errors:
            parser.error('Number of reconnect timeouts must be less than sequenctial errors')

    args.start_time = time.time()

    # Use the current git hash to seed the random number generator,
    # to avoid the number of test cases for a particular snapshot increasing
    # each time the view is built in the CI system.

    git_rev = subprocess.run(
        ['git', 'rev-parse', 'HEAD'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    # Git hash is hexadecimal string
    args.seed_base = int(git_rev.stdout[0].strip(), 16)


def webserver_test(args):
    try:
        response = urllib.request.urlopen(
            'http://' + args.ip + ':' + str(args.start_port), timeout=10)
        html = response.read().decode('utf-8')
        print(html)

    except urllib.error.URLError as e:
        if isinstance(e.reason, socket.timeout):
            print('ERROR: Could not connect to device: {}'.format(e))
        else:
            print('ERROR: URL error: {}'.format(e))

    except socket.timeout as e:
        print('ERROR: Could not connect to device: {}'.format(e))


if __name__ == '__main__':
    # Defaults
    packets = 10000
    packet_size_limit = 100
    delay_between_packets = 0
    remote_processes = 1
    remote_ports = 1
    local_port_udp = 15999
    protocol = "UDP"
    test = 'reflect'

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
    parser.add_argument('--protocol', default=protocol, type=str, choices=['UDP', 'TCP'],
                        help="TCP/UDP protocol (default='%s')" % protocol)
    parser.add_argument('--packets', default=packets, type=int,
                        help="Number of packets to send (defaults='%s')" % packets)
    parser.add_argument('--packet-size-limit', default=packet_size_limit, type=int,
                        help="Size of packets to send (defaults='%s')" % packet_size_limit)
    parser.add_argument('--delay-between-packets', default=delay_between_packets, type=float,
                        help="Delay between packets (defaults='%s')" % delay_between_packets)
    parser.add_argument('--test', default=test, type=str,
                        help="Which test to run (default='%s')" % test)
    parser.add_argument('--halt-sequential-errors', default=0, type=int,
                        help="After how many sequential errors does the test halt, 0='--packets' (default='%s')" % 0)
    parser.add_argument('--num-timeouts-reconnect', default=0, type=int,
                        help="After how many timeouts to attempt a reconnect, typcailly UDP, 0=no reconnect (default='%s')" % 0)
    args = parser.parse_args()

    check_and_set_args(args)

    # udp_bind_test()
    # multicast_test()
    if args.test == 'webserver':
        webserver_test(args)
    elif args.test == 'connection':
        connect_test(args)
    else:
        if args.protocol == 'UDP' or args.protocol == 'TCP':
            reflect_test(args)
        else:
            print("Unknown protocol")

    print("Kill target")
    kill_remote_device(args)
