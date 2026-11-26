# test

Unit test orchestrator.

## Overview

This unit runs kernel unit tests during boot and prints their aggregate results through `test.harness`.

## Boot Registration

- `asuro.test.init` resets the harness counters at the middle barrier.
- `asuro.test.run.standard` runs the standard suite at the late barrier.
- `asuro.test.run.complex` runs after the standard suite when complex tests are enabled.
- `asuro.test.finish` prints the summary after all enabled suites finish.

## Suite selection

Builds with `UNIT_TESTS` register the boot tests. `runAllTests` calls the standard suites in sequence. Builds that also define `UNIT_TESTS_COMPLEX` run the additional suites in `runComplexTests` afterward.

To register a new suite, import its unit in `test.pas` and call its `UnitTest` procedure from the appropriate runner. Follow the [test harness guide](test.harness.md) when writing the procedure.

## Serial reporting

The boot runner calls `test.harness.Init` before the suites and `test.harness.Print` after them. The final serial output includes one line for unit totals and one for assertion totals.

```text
[test] 2 units tested, 1 passed, 1 failed.
[test] 8 tests run, 7 passed, 1 failed.
```

CI reads the final `tests run` line for the aggregate assertion result. With `--testonly`, the x86 kernel requests power-off after printing both summaries.
