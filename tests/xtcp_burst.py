# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import socket
import random
import string
import time
import argparse
import sys
from multiprocessing import Pool
import copy
import xtcp_support

# This test script can run a bursty reflect test (sending and receiving)
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
#   python xtcp_burst.py --ip 192.168.200.198 --start-port 15533 --remote-processes 1 --remote-ports 1 \
#   --protocol TCP --packets 100 --delay-between-packets 0.002 --halt-sequential-errors 11 --num-timeouts-reconnect 3
#
# This scripts stores issues in the list variables 'failures', these are then printed out at the end of the test for
# the pytest script running this one to pick up and parse.
#   Issues are reported prefixed with 'Info:', 'LOSS:' or 'ERROR:'.


def process_test(args):
    # Each thread now has a different seed
    random.seed(args.seed_base + args.start_port)
    tests_to_perform = args.packets
    failures = []

    (failures, sock) = xtcp_support.attempt_connect(failures, args)
    if sock is None:
        args.failures = failures
        return args

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
        message1 = ''.join(random.choice(string.ascii_lowercase[1:]) for c in range(length_of_message)).encode('ascii')
        message2 = ''.join(random.choice(string.ascii_lowercase[1:]) for c in range(length_of_message)).encode('ascii')
        message3 = ''.join(random.choice(string.ascii_lowercase[1:]) for c in range(length_of_message)).encode('ascii')

        try:
            send_len = sock.send(message1)
            time.sleep(0.001)  # Small delay to try and get packets to arrive separately
            send_len += sock.send(message2)
            time.sleep(0.001)  # Small delay to try and get packets to arrive separately
            send_len += sock.send(message3)

            recv_len = 0
            returned_message = b''
            while recv_len < send_len:
                # Receive up to one MTU of data
                returned_message += sock.recv(1500)
                recv_len = len(returned_message)

            # if returned_message != message:
            if message1[::-1] not in returned_message:  # Reverse string
                failures.append(
                    'LOSS:' + xtcp_support.build_message_report('miss', args, sock, length_of_message, message1, returned_message)
                )

            if message2[::-1] not in returned_message:  # Reverse string
                failures.append(
                    'LOSS:' + xtcp_support.build_message_report('miss', args, sock, length_of_message, message2, returned_message)
                )

            if message3[::-1] not in returned_message:  # Reverse string
                failures.append(
                    'LOSS:' + xtcp_support.build_message_report('miss', args, sock, length_of_message, message3, returned_message)
                )

            # timeout checks, force action to be 'n' sequential timeouts
            num_timeouts = 0
            num_exceptions = 0

        except socket.timeout:
            num_timeouts += 1
            failures.append(
                'LOSS:' + xtcp_support.build_basic_report('time', args, sock, length_of_message)
            )

            if args.num_timeouts_reconnect != 0 and num_timeouts >= args.num_timeouts_reconnect:
                # Reconnect
                (failures, sock) = xtcp_support.attempt_connect(failures, args, sock)
                if sock is None:
                    break

            if args.halt_sequential_errors != 0 and num_timeouts >= args.halt_sequential_errors:
                failures.append(
                    'ERROR:' + xtcp_support.build_basic_report('seq-time', args, sock, length_of_message)
                )
                break

        except socket.error as err:
            num_exceptions += 1
            failures.append(
                'LOSS:' + xtcp_support.build_exception_report('err', args, sock, err, length_of_message)
            )

            # Reconnect
            (failures, sock) = xtcp_support.attempt_connect(failures, args, sock)
            if sock is None:
                break

            if args.halt_sequential_errors != 0 and num_exceptions >= args.halt_sequential_errors:
                failures.append(
                    'ERROR:' + xtcp_support.build_exception_report('seq-err', args, sock, err, length_of_message)
                )
                break

    if tests_to_perform != 0:
        failures.append(
            'Info:' + xtcp_support.build_basic_report('runs', args, sock, args.packets - tests_to_perform)
        )

    if sock is not None:
        sock.shutdown(socket.SHUT_RDWR)
        sock.close()

    # If printing progress '.' then add newline
    print('')
    args.failures = failures
    return args


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

    pool.map_async(process_test, args_pool, 1, callback=xtcp_support.print_errors)

    pool.close()
    pool.join()
    pool.terminate()


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
                        help="After how many timeouts to attempt a reconnect, typically UDP, 0=no reconnect (default='%s')" % 0)
    args = parser.parse_args()

    xtcp_support.check_and_set_args(args, parser)

    if args.protocol == 'UDP' or args.protocol == 'TCP':
        reflect_test(args)
    else:
        print("Unknown protocol")

    print("Kill target")
    xtcp_support.kill_remote_device(args)
