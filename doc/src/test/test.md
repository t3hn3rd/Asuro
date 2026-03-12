# test

Unit test orchestrator.

## Overview

This unit provides a central entry point for running all kernel unit tests. It registers two boot entries: an early stub (`asuro.test.init`) and a late runner (`asuro.test.run`) that invokes every unit's `UnitTest` procedure in sequence.

## Boot Registration

- `asuro.test.init` at `middle` barrier — placeholder for future test framework setup.
- `asuro.test.run` at `late` barrier — calls all unit test procedures after the full kernel is initialised.

## Dependencies

- `boot.mgr`
- All units whose `UnitTest` procedure is invoked (see list below)

## Procedures

### init

```pascal
procedure init;
```

Stub initialiser registered at the `middle` barrier. Currently a no-op; reserved for future test framework configuration.

### runAllTests

```pascal
procedure runAllTests;
```

Invokes `UnitTest` on every registered test suite:

- `core.strings`
- `driver.bus.usb.types`, `driver.bus.usb.core`
- `driver.bus.usb.uhci`, `driver.bus.usb.ohci`, `driver.bus.usb.ehci`, `driver.bus.usb.xhci`
- `driver.bus.usb.hub`
- `driver.hid.usb.keyboard`, `driver.hid.usb.mouse`
- `core.ds.fifo`, `core.ds.cfifo`, `core.ds.cfifols`, `core.ds.lifo`, `core.ds.circ`
- `wasm.test`
- `core.ds.minh`, `core.ds.maxh`, `core.ds.prio`
- `driver.storage.vfs`, `driver.storage.test`
- `core.enc.fnv1a`, `core.enc.djb2`
- `core.ds.bloom`
- `core.fmt.json`

## Notes

- Each `UnitTest` procedure logs its own pass/fail counts via `io.syslog`.
- The unit is included in `boot.mgr`'s `uses` clause as a silo unit to ensure its `initialization` section runs.
