# Copyright 2024-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.


def pytest_addoption(parser):
    parser.addoption(
        "--seed",
        action="store",
        default=None,
        type=int,
        help="Seed used for initialising the random number generator in tests",
    )
    parser.addoption(
        "--level",
        action="store",
        default="smoke",
        choices=["smoke", "nightly", "weekend", "quick"],
        help="Test coverage level",
    )
    parser.addoption(
        "--adapter-id",
        action="store",
        default=None,
        help="DUT adapter-id when running HW tests",
    )
    parser.addoption(
        "--eth-intf",
        action="store",
        default=None,
        help="DUT adapter-id when running HW tests",
    )
    parser.addoption(
        "--test-duration",
        action="store",
        default=None,
        help="Test duration in seconds",
    )
    parser.addoption(
        "--phy",
        action="store",
        default="phy0",
        choices=["phy0", "phy1"],
        help="The PHY to run HW tests on. Default is phy0",
    )
    parser.addoption(
        "--session-timeout",
        action="store",
        default="600",
        help="The maximum time for the tests to run",
    )
