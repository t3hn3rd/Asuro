# core

Core subsystem late initialiser.

## Overview

This unit performs late-stage core initialisation that depends on the RTC being available. Currently it seeds the pseudo-random number generator from the real-time clock.

## Boot Registration

Registered with `boot.mgr` as `core` at the `late` barrier.

## Dependencies

- `boot.mgr`
- `core.rand`
- `driver.timer.rtc`

## Procedures

### init

```pascal
procedure init;
```

Seeds `core.rand.srand` with a value derived from the current RTC date/time (seconds, minutes, hours, day), ensuring the PRNG produces different sequences across reboots.
