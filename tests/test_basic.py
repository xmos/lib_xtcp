import xmostest
import re

# This tester is a mashup of the built in ComparisonTester and
# the AnalogueInputTester from USB Audio. It checks for errors on
# the XMOS device and checks the output from a python program
# running on a PC
class xTCPTester(xmostest.Tester):
    def __init__(self, total_connections, packets, protocol, product, group,
                 test, config = {}, env = {}):
        super(xTCPTester, self).__init__()
        self.register_test(product, group, test, config)
        self._total_connections = total_connections
        self._packets = packets
        self._protocol = protocol
        self._test = (product, group, test, config, env)

    def record_failure(self, failure_reason):
        # Append a newline if there isn't one already
        if not failure_reason.endswith('\n'):
            failure_reason += '\n'
        self.failures.append(failure_reason)
        print "Failure reason: {}".format(failure_reason) # Print without newline
        self.result = False

    def run(self, xc_output, python_output):
        self.result = True
        self.failures = []
        total_connections = self._total_connections
        packets = self._packets
        protocol = self._protocol
        (product, group, test, config, env) = self._test

        if isinstance(python_output, str):
            python_output = python_output.split('\n')

        while(python_output[-1] == ''):
            del python_output[-1]

        # Check for any xC device errors
        for line in (xc_output + python_output):
            if re.match('.*ERROR|.*error|.*Error|.*Problem', line):
                self.record_failure(line)

        # Check the board is listening on every port
        found_connections = 0
        for i in range(len(xc_output)):
            if(re.match('Listening on port: [0-9]+$', xc_output[i])):
                found_connections += 1

        if found_connections < total_connections:
            self.record_failure("Incorrect amount of listening ports created on device\n" +
                                "  Expected ports: {}".format(total_connections) +
                                "  Actual ports:   {}".format(found_connections))

        udp_max_error = int(packets * total_connections * 0.01)
        total_errors = -1
        for i in range(len(python_output)):
            if(re.match('Lost_packets: [0-9]+.*$', python_output[i])):
                total_errors = int(python_output[i].split(' ')[1])
                break

        if total_errors == -1:
            self.record_failure("Could not find the python script's error output")

        # Accept a 1% error rate for UDP?
        if protocol == "UDP":
            if total_errors > udp_max_error:
                self.record_failure("Packet error rate too high \n" +
                                    "  Allowable loss rate: {} packets\n".format(udp_max_error) +
                                    "  Actual loss rate:    {} packets\n".format(total_errors))

        # Accept no errors for TCP
        else:
            if total_errors > 0:
                self.record_failure("Packet error rate too high \n" +
                                    "  Allowable loss rate: 0 packets\n" +
                                    "  Actual loss rate:    {} packets\n".format(total_errors))

        output = {'python_output':''.join(python_output),
                  'device_output':''.join(xc_output)}

        if not self.result:
            output['failures'] = ''.join(self.failures)

        xmostest.set_test_result(product,
                                 group,
                                 test,
                                 config,
                                 self.result,
                                 env={},
                                 output=output)


def test(packets, delay, device, ip, remote_processes, connections, interface, protocol, library):
    setup = '{}_{}_{}_{}_{}'.format(remote_processes, connections, protocol, device, interface)
    binary = 'xtcp_bombard_{}/bin/{}/xtcp_bombard_{}_{}.xe'.format(library.lower(), setup, library.lower(), setup)

    tester = xmostest.CombinedTester(2, xTCPTester(remote_processes*connections,
                                     packets, protocol,
                                    'lib_xtcp', device.lower() + '_configuration_tests', '{}_{}'.format(setup, library), {}))

    resources = xmostest.request_resource('xtcp_resources', tester)

    run_job = xmostest.run_on_xcore(resources[device.lower()], binary,
                                    tester=tester[0],
                                    enable_xscope=True,
                                    timeout=30)

    START_PORT = 15533

    server_job = xmostest.run_on_pc(resources['host'],
                                    ['python', 'xtcp_ping_pong.py',
                                    '--ip', '{}'.format(ip),
                                    '--start-port', '{}'.format(START_PORT),
                                    '--remote-processes', '{}'.format(remote_processes),
                                    '--remote-ports', '{}'.format(connections),
                                    '--protocol', '{}'.format(protocol),
                                    '--packets', '{}'.format(packets),
                                    '--delay-between-packets', '{}'.format(delay)],
                                    timeout=60*2,
                                    tester=tester[1],
                                    initial_delay=20)

def runtest():
    # Check if the test is running in an environment where
    # it can access the machine with the slice kit attached
    args = xmostest.getargs()
    if not args.remote_resourcer:
        # Abort the test
        print 'Remote resourcer not avaliable'
        return

    if xmostest.testlevel_is_at_least(xmostest.get_testlevel(), 'smoke'):
        packets = 1000
    elif xmostest.testlevel_is_at_least(xmostest.get_testlevel(), 'nightly'):
        packets = 10000
    else: # weekend
        packets = 100000

    tests = [# device     ip               processes ports mii    protocol
             ['EXPLORER', '192.168.1.198', 1,        1,    'ETH', 'UDP', 'UIP'],
             ['EXPLORER', '192.168.1.198', 1,        1,    'ETH', 'TCP', 'UIP'],
             ['EXPLORER', '192.168.1.198', 2,        2,    'ETH', 'UDP', 'UIP'],
             ['EXPLORER', '192.168.1.198', 2,        2,    'ETH', 'TCP', 'UIP'],

             ['MICARRAY', '192.168.1.197', 1,        1,    'RAW', 'UDP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 1,        1,    'RAW', 'TCP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'RAW', 'UDP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'RAW', 'TCP', 'UIP'],

             ['MICARRAY', '192.168.1.197', 1,        1,    'ETH', 'UDP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 1,        1,    'ETH', 'TCP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'ETH', 'UDP', 'UIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'ETH', 'TCP', 'UIP'],

             ['SLICEKIT', '192.168.1.196', 1,        1,    'RAW', 'UDP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 1,        1,    'RAW', 'TCP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 2,        2,    'RAW', 'UDP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 2,        2,    'RAW', 'TCP', 'UIP'],

             ['SLICEKIT', '192.168.1.196', 1,        1,    'ETH', 'UDP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 1,        1,    'ETH', 'TCP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 2,        2,    'ETH', 'UDP', 'UIP'],
             ['SLICEKIT', '192.168.1.196', 2,        2,    'ETH', 'TCP', 'UIP'],

             ['EXPLORER', '192.168.1.198', 1,        1,    'ETH', 'UDP', 'LWIP'],
             ['EXPLORER', '192.168.1.198', 1,        1,    'ETH', 'TCP', 'LWIP'],
             ['EXPLORER', '192.168.1.198', 2,        2,    'ETH', 'UDP', 'LWIP'],
             ['EXPLORER', '192.168.1.198', 2,        2,    'ETH', 'TCP', 'LWIP'],

             ['MICARRAY', '192.168.1.197', 1,        1,    'RAW', 'UDP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 1,        1,    'RAW', 'TCP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'RAW', 'UDP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'RAW', 'TCP', 'LWIP'],

             ['MICARRAY', '192.168.1.197', 1,        1,    'ETH', 'UDP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 1,        1,    'ETH', 'TCP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'ETH', 'UDP', 'LWIP'],
             ['MICARRAY', '192.168.1.197', 2,        2,    'ETH', 'TCP', 'LWIP'],
            ]

    for conf in tests:
        test(packets, 0.002, *conf)
