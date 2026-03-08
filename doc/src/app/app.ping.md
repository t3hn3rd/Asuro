# app.ping

ICMP ping command that sends echo requests and reports round-trip times.

## Overview

`app.ping` registers the `PING` shell command. Given an IPv4 address, it sends 10 ICMP echo requests with a 1-second delay between each, printing the round-trip time or an error reason for each attempt. A 5-second timeout is enforced per ping. Per-invocation state is heap-allocated so multiple terminal instances can ping concurrently without interfering with each other.

## Dependencies

- `io.stdio`, `debug.tracer`
- `arch.x86.bda`
- `driver.net.types`, `driver.net.proto.icmp`, `driver.net.util`
- `core.strings`
- `proc.mgr`
- `core.util`, `arch.x86.util`
- `memory.heap`

## Constants

### PING_TIMEOUT_MS
`5000` — Per-ping timeout in milliseconds.

## Types

### TPingResult

```pascal
TPingResult = (prWaiting, prGotReply, prGotError);
```

State of a single in-flight ping.

### TPingState / PPingState

Per-invocation state record allocated on the heap.

| Field | Type | Description |
|---|---|---|
| `Result` | `TPingResult` | Current result state |
| `ReplyTimeMS` | `uint64` | Round-trip time in timer ticks |
| `ErrorReason` | `TARPErrorCode` | Error code if `prGotError` |
| `SendTime` | `uint64` | BIOS tick counter value at send time |

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `PING` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Parses the first parameter as an IPv4 address string using `stringToIPv4`. Allocates a `TPingState` record and sends 10 ICMP requests in a loop. Between each request it spin-yields via `proc.mgr.proc_yield` until the reply or error callback fires, or until the timeout expires. Sleeps 1 second between pings using `proc.mgr.proc_sleep_ms`. Frees the state record and IP buffer on completion.

### on_reply (internal)

ICMP callback: records the elapsed time and sets `Result` to `prGotReply`.

### on_error (internal)

ICMP callback: records the error reason and sets `Result` to `prGotError`.

## Notes

Round-trip time is reported in BIOS timer ticks (the counter runs at approximately 1024 Hz), not milliseconds. Error reasons include: `aecFailedToResolveHost`, `aecNoRouteToHost`, `aecTimeout`, and `aecTTLExpired`.
