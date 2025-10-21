# Copyright 2016-2025 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.

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
