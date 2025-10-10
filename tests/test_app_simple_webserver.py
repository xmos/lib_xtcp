# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

import time
import pathlib
import subprocess
from hardware_test_tools import XcoreApp


def test_app_simple_webserver(request):
    adapter_id = request.config.getoption("--adapter-id")
    assert adapter_id is not None, "Error: Specify a valid adapter-id"

    expected_response = '<!DOCTYPE html>\n' \
        '<html><head><title>Hello world</title></head>\n' \
        '<body>Hello World!</body></html>\n'

    web_response = run_test('192.168.200.178', adapter_id)

    assert expected_response in web_response.stdout


def run_test(ip, adapter_id):
    binary = pathlib.Path(
        '../examples/app_simple_webserver/bin/app_simple_webserver.xe')

    assert binary.exists(), f'Error: Binary not found: {binary}'

    print(f'Target IP address: {ip}')

    test_stdout = ""
    web_response = ""

    with XcoreApp.XcoreApp(binary, adapter_id, attach='xscope') as xcoreapp:
        time.sleep(15)  # Wait for IFUP

        web_response = subprocess.run(
            ['python', 'xtcp_ping_pong.py', '--ip', ip,
                '--start-port', '80', '--test', 'webserver'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        xcoreapp.terminate()
        test_stdout = xcoreapp.proc_stdout

    print(test_stdout)
    print(web_response)

    return web_response
