# Copyright 2024-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.


def pytest_addoption(parser):
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
        "--multi-phy",
        action="store",
        default="dual",
        choices=["dual", "single"],
        help="DUT (xcore-ai) board configuration for the number of PHYs",
    )
