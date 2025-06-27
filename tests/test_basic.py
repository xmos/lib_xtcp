# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import pytest
import re
import math
import time
import pathlib
import subprocess
from hardware_test_tools import XcoreApp


@pytest.mark.parametrize('protocol', ['UDP', 'TCP'])
@pytest.mark.parametrize('library', ['UIP', 'LWIP'])
@pytest.mark.parametrize('processes', [1, 2])
def test_basic(request, protocol, library, processes):
    dut_ip = '192.168.200.198'
    dut_ports_per_proc = processes  # TODO parameterise this independently???

    tester = RunXtcp(processes, dut_ports_per_proc, protocol)
    tester.setup(request)

    tester.run_test(0.002, 'EXPLORER', dut_ip, 'ETH', library)

    tester.check_xrun()
    tester.check_python()

    assert len(tester.failures()) == 0


class CollectFailures():
    def __init__(self):
        self._failures = []

    def record_failure(self, failure_reason):
        # Append a newline if there isn't one already
        if not failure_reason.endswith('\n'):
            failure_reason += '\n'
        self._failures.append(failure_reason)
        print("Failure reason: {}".format(failure_reason))
        self.result = False

    def failures(self):
        return self._failures


class RunXtcp(CollectFailures):
    def __init__(self, processes, ports, protocol):
        super(RunXtcp, self).__init__()
        self._adapter_id = None
        self.processes = processes
        self.ports = ports
        self.protocol = protocol

        self.python_output = ""
        self.xrun_stdout = ""

    def setup(self, request):
        self.adapter_id = request.config.getoption("--adapter-id")
        assert self.adapter_id is not None, "Error: Specify a valid adapter-id"

        self.multi_phy = request.config.getoption("--multi-phy")
        assert self.multi_phy is not None, "Error: Specify a valid multi-phy"

        level = request.config.getoption("--level")
        if level == 'quick':
            self.packets = 10
        elif level == 'smoke':
            self.packets = 1000
        elif level == 'nightly':
            self.packets = 10000
        else:  # weekend
            self.packets = 100000

    def run_test(self, delay, device, ip, interface, library):
        setup = f'{self.processes}_{self.ports}_{self.protocol}_{device}_{interface}'
        binary = pathlib.Path(f'xtcp_bombard_{library.lower()}/bin/{setup}/xtcp_bombard_{library.lower()}_{setup}.xe')

        assert binary.exists(), 'Found test binary'

        START_PORT = "15533"

        with XcoreApp.XcoreApp(binary, self.adapter_id, attach='xscope') as xcoreapp:
            time.sleep(15)  # Wait for IFUP

            self.python_output = subprocess.run(
                [
                    'python', 'xtcp_ping_pong.py', '--ip', ip,
                    '--start-port', START_PORT,
                    '--remote-processes', f'{self.processes}',
                    '--remote-ports', f'{self.ports}',
                    '--protocol', self.protocol,
                    '--packets', f'{self.packets}',
                    '--delay-between-packets', f'{delay}',
                    '--halt-sequential-errors', f'{11}',
                    '--num-timeouts-reconnect', f'{3}'
                ],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )

            xcoreapp.terminate()
            self.xrun_stdout = xcoreapp.proc_stdout

        print("XRUN output:")
        print(self.xrun_stdout)

        assert self.python_output.returncode == 0, "python script xtcp_ping_pong.py did not run"

    def check_python(self):
        if isinstance(self.python_output, subprocess.CompletedProcess):
            output = self.python_output.stdout
        else:
            output = self.python_output

        total_errors = 0
        total_losses = 0
        python_valid = False
        total_runs = self.packets * self.processes * self.ports
        achieved_runs = self.packets * self.processes * self.ports

        # Check for any test output errors
        for line in output.splitlines():
            if re.match('.*ERROR:|.*error:|.*Error:|.*Problem:|.*FAIL:', line):
                total_errors += 1
                self.record_failure(line)

            elif re.match('.*Loss:|.*LOSS:', line):
                total_losses += 1
                print(line)

            elif re.match('.*Info:|.*INFO:', line):
                print(line)
                split = line.split('\t')
                if len(split) > 1 and 'runs' in split[1]:
                    achieved_runs -= self.packets
                    achieved_runs += int(split[-1])

            elif (re.match('Lost_packets: [0-9]+.*$', line)):
                python_valid = True

        if python_valid is not True:
            self.record_failure("Could not find the python script's error output")

        # Accept a 1% error rate for UDP?
        if self.protocol == "UDP":
            test_threshold = math.ceil(self.packets * self.processes * self.ports * 0.01)

        else:  # Accept no errors for TCP
            test_threshold = 0

        if total_losses > test_threshold:
            self.record_failure(
                f"Packet error rate too high for {self.protocol}\n" +
                f"  Allowable losses: {test_threshold} packets\n" +
                f"  Actual losses:    {total_losses} packets\n" +
                "  Loss rate:        {0:.2f} %\n".format(total_losses * 100.0 / achieved_runs) +
                f"  Runs:             {achieved_runs}/{total_runs} packets (achieved/requested)\n"
            )

    def check_xrun(self):
        # Check the board is listening on every port
        num_connections = self.processes * self.ports
        found_connections = 0
        num_interfaces = 0

        for line in self.xrun_stdout.splitlines():
            if (re.match('Listening on port: [0-9]+$', line)):
                found_connections += 1

            elif 'IFUP' in line:
                num_interfaces += 1

        if found_connections != num_connections:
            self.record_failure(
                "Incorrect number of listening ports created on device\n" +
                "  Expected ports: {}".format(num_connections) +
                "  Actual ports:   {}".format(found_connections)
            )

        if num_interfaces != self.processes:
            self.record_failure(
                "Incorrect number of interfaces up" +
                f"  Expected: {self.processes}" +
                f"  Actual: {num_interfaces}"
            )
