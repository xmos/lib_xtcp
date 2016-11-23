import xmostest
import re

# This tester is a mashup of the built in ComparisonTester and
# the AnalogueInputTester from USB Audio. It checks for errors on
# the XMOS device and checks the output from a python program 
# running on a PC
class webTester(xmostest.Tester):
    def __init__(self, expected_response, ip, product, group, 
                 test, config = {}, env = {}):
        super(webTester, self).__init__()
        self.register_test(product, group, test, config)
        self._expected_response = expected_response
        self._ip = ip
        self._test = (product, group, test, config, env)

    def record_failure(self, failure_reason):
        # Append a newline if there isn't one already
        if not failure_reason.endswith('\n'):
            failure_reason += '\n'
        self.failures.append(failure_reason)
        print 'Failure reason: {}'.format(failure_reason) # Print without newline
        self.result = False

    def run(self, xc_output, python_output):
        self.result = True
        self.failures = []
        expected_response = self._expected_response
        ip = self._ip
        (product, group, test, config, env) = self._test

        if isinstance(python_output, str):
            python_output = python_output.split('\n')

        while(python_output[-1] == ''):
            del python_output[-1]
        
        # Check for any xC device errors
        for line in (xc_output + python_output):
            if re.match('.*ERROR|.*error|.*Error|.*Problem', line):
                self.record_failure('Error: ' + line)

        if python_output[0] != expected_response:
            self.record_failure('Response from device did not match expected response\n' +
                                '  Expected:\n{}'.format(expected_response) +
                                '  Actual:\n{}'.format(python_output))

        for line in xc_output:
            if re.match('IP Address: [0-9].[0-9].[0-9].[0-9]', line):
                found_ip = line.strip('IP Address: ').strip('\n')
                if(found_ip != ip):
                    self.record_failure('Differing IP address used by device than expected\n' +
                                        '  Expected: {}\n'.format(ip) + 
                                        '  Found:    {}'.format(found_ip))
        
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

def test(device, ip, expected_response):
    binary = '../examples/app_simple_webserver/bin/UIP/app_simple_webserver_UIP.xe'

    tester = xmostest.CombinedTester(2, webTester(expected_response, ip,
                                    'lib_xtcp', device + '_configuration_tests', 'webserver', {}))
    
    resources = xmostest.request_resource('xtcp_resources', tester)

    if not resources[device]:
        # Abort the test
        print 'Resource \'{}\' not avaliable'.format(device)
        return

    if not resources['host']:
        # Abort the test
        print 'Resource \'host\' not avaliable'
        return

    run_job = xmostest.run_on_xcore(resources[device], binary,
                                    tester=tester[0],
                                    enable_xscope=True,
                                    timeout=30)

    server_job = xmostest.run_on_pc(resources['host'],
                                    ['python', 'xtcp_ping_pong.py',
                                    '--ip', '{}'.format(ip),
                                    '--start-port', '80',
                                    '--test', 'webserver'],
                                    timeout=30,
                                    tester=tester[1],
                                    initial_delay=15)

def runtest():
    # Check if the test is running in an environment where
    # it can access the machine with the devices attached
    args = xmostest.getargs()
    if not args.remote_resourcer:
        # Abort the test
        print 'Remote resourcer not avaliable'
        return

    test('slicekit', '192.168.2.5', '<!DOCTYPE html>' +
                                    '<html><head><title>Hello world</title></head>' +
                                    '<body>Hello World!</body></html>\n')
