# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import socket
import time
import argparse
import subprocess


def print_errors(args_compound):
    # Flatten list
    failure_list = [item for sublist in args_compound for item in sublist.failures]

    if len(failure_list) > 0:
        print('    \ttype\tid\ttime\tlocal\tremote\tsent_l\t?ret_l\t?err\t?mess\t?recv')
        print(''.join(failure_list))

    args = args_compound[0]
    print('Lost_packets: {} of {}'.format(len(failure_list),
                                          args.packets * args.remote_processes * args.remote_ports))

    print(f'Info: Bandwidth: {((8 * args.packet_size_limit * (args.packets * args.remote_processes * args.remote_ports)) / (time.time() - args.start_time)) / (1024 * 1024):.2f} Mb/s')


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


# def format_message(message, width):
#     return '\n  '.join([message[i:i+width]
#                         for i in range(0, len(message), width)])


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


def check_and_set_args(args, parser):
    if args.ip is None:
        parser.error('Need IP address')

    if args.start_port is None:
        parser.error('Need starting port')

    if args.packet_size_limit > 1460:
        parser.error('Packet size is too large and will be split')

    if args.num_timeouts_reconnect != 0 and args.halt_sequential_errors != 0:
        if args.num_timeouts_reconnect > args.halt_sequential_errors:
            parser.error('Number of reconnect timeouts must be less than sequential errors')

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
