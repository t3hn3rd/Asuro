# driver.io.serial

Serial port (UART 16550) driver.

## Overview

This unit provides initialisation and byte-level I/O for the four standard PC serial ports (COM1–COM4). It configures the UART for 8N1 operation at a specified baud rate, enables the FIFO, and provides send/receive routines with configurable busy-wait timeouts. A string send helper appends CR+LF, and a hex send helper transmits a `0x`-prefixed hexadecimal representation.

## Dependencies

- (none — uses inline assembly for I/O port access)

## Constants

### COM Port Base Addresses
| Constant | Value | Description |
|---|---|---|
| `COM1` | `$3F8` | First serial port |
| `COM2` | `$2F8` | Second serial port |
| `COM3` | `$3E8` | Third serial port |
| `COM4` | `$2E8` | Fourth serial port |

## Functions and Procedures

### initPort
```pascal
procedure initPort(port: uint16; baud: uint32);
```
Initialises the UART at `port` for the given baud rate:
1. Disables interrupts.
2. Sets the Divisor Latch Access Bit (DLAB) and writes the baud rate divisor (`115200 div baud`).
3. Configures 8 data bits, no parity, 1 stop bit (8N1).
4. Enables and clears the FIFO with a 14-byte trigger level.
5. Clears the DLAB.

### send
```pascal
procedure send(port: uint16; data: uint8; timeout: uint32);
```
Busy-waits on the Transmit Holding Register Empty bit of the Line Status Register (LSR) for up to `timeout` iterations, then writes `data` to the port's data register.

### receive
```pascal
function receive(port: uint16; timeout: uint32): uint8;
```
Busy-waits on the Data Ready bit of the LSR for up to `timeout` iterations, then reads and returns the byte from the data register. Returns `$00` on timeout.

### sendString
```pascal
procedure sendString(port: uint16; s: string);
```
Transmits each character of `s` followed by CR (`$0D`) and LF (`$0A`).

### sendHex
```pascal
procedure sendHex(port: uint16; value: uint32);
```
Transmits the string `0x` followed by the 8-digit uppercase hexadecimal representation of `value`.

### soutb / sinb (internal)
Inline assembly wrappers for the `OUT` and `IN` instructions, each followed by an `io_wait` call (a zero-write to port `$80`) to satisfy slow I/O device timing requirements.

## Notes

- No interrupt-driven receive buffering is implemented; all I/O is polled.
- `io_wait` is inserted after every port access to accommodate slow ISA-speed devices.
