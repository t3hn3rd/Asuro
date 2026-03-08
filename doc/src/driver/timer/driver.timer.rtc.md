# driver.timer.rtc

CMOS Real-Time Clock (RTC) driver.

## Overview

This unit provides access to the PC CMOS Real-Time Clock via I/O ports `$70` (index) and `$71` (data). It reads all date and time fields from CMOS registers, converts them from BCD to binary, and caches the result in a `TDateTime` record. It also enables the RTC periodic interrupt for use as a system timer tick source.

## Dependencies

- (none — uses direct I/O port access)

## Types

### TDateTime
Cached date and time record populated by `update`:

| Field | Type | Description |
|---|---|---|
| `Seconds` | `uint8` | Seconds (0–59) |
| `Minutes` | `uint8` | Minutes (0–59) |
| `Hours` | `uint8` | Hours (0–23, 24-hour format) |
| `Weekday` | `uint8` | Day of week (1=Sunday … 7=Saturday) |
| `Day` | `uint8` | Day of month (1–31) |
| `Month` | `uint8` | Month (1–12) |
| `Year` | `uint8` | Year within century (0–99) |
| `Century` | `uint8` | Century (e.g. 20 for years 2000–2099) |

## Functions and Procedures

### init
```pascal
procedure init;
```
Enables RTC periodic interrupts by setting bit 6 (`$40`) of CMOS register `$8B` (Status Register B). The periodic interrupt rate is left at the CMOS default (typically 1024 Hz).

### update
```pascal
procedure update;
```
Reads all eight CMOS RTC registers (seconds, minutes, hours, weekday, day, month, year, century). Converts each from BCD to binary using `BCDToUint8`. Stores the results in the internal `TDateTime` cache.

### getDateTime
```pascal
function getDateTime: TDateTime;
```
Calls `update` to refresh the cached record, then returns a copy of it.

### weekdayToString
```pascal
function weekdayToString(weekday: uint8): string;
```
Maps a weekday value (1–7) to its English name string (e.g. `1` → `'Sunday'`).

### BCDToUint8 (internal)
```pascal
function BCDToUint8(bcd: uint8): uint8;
```
Converts a packed BCD byte to its decimal value: `(bcd shr 4) * 10 + (bcd and $0F)`.

## Notes

- CMOS register access requires writing the register index to port `$70` and reading/writing data at port `$71`. NMI is disabled during access by setting bit 7 of the index byte.
- The RTC may return inconsistent data if read during an update cycle. A robust implementation checks the Update-In-Progress (UIP) flag in Status Register A before reading; this implementation does not do so and may occasionally return a one-second-stale value.
