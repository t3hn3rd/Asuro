# app.testcmd

Simple test command that demonstrates incremental output with timed delays.

## Overview

`app.testcmd` registers the `TEST` shell command, which prints five numbered lines to stdout with a 1-second pause between each. Its primary purpose is to demonstrate that long-running commands execute as preemptive processes, with output appearing incrementally in the terminal without blocking the rest of the system.

## Dependencies

- `io.stdio`
- `proc.mgr`
- `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `TEST` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Prints the lines `Test output 1 of 5` through `Test output 5 of 5` to `stdout_buf`, calling `proc.mgr.proc_sleep_ms(1000)` between each line (except after the last).

## Notes

This unit is a development and diagnostic aid. The command accepts no parameters.
