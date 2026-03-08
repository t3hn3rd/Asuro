# driver.net.util

Network utility functions for address handling, packet context management, and checksum computation.

## Overview

This unit provides stateless helper routines used across all network protocol layers. It covers copying and comparing MAC and IPv4 addresses, converting address strings to binary, packet context allocation and cleanup, RFC 1071 checksum calculation, and common packet-forwarding helpers.

## Dependencies

- `driver.net.types`
- `core.memory`

## Functions and Procedures

### Address Copy
```pascal
procedure copyMAC(dst: PMACAddress; src: PMACAddress);
procedure copyIPv4(dst: PIPv4Address; src: PIPv4Address);
```
Copies a 6-byte MAC or 4-byte IPv4 address from `src` to `dst`.

### Address Comparison
```pascal
function MACEqual(a, b: TMACAddress): boolean;
function IPEqual(a, b: TIPv4Address): boolean;
```
Returns `true` if both addresses are identical byte-for-byte.

### Address Parsing
```pascal
function stringToMAC(s: string): TMACAddress;
function stringToIPv4(s: string): TIPv4Address;
```
Parses a colon-delimited MAC address string (`AA:BB:CC:DD:EE:FF`) or a dotted-decimal IPv4 string (`A.B.C.D`) into the corresponding binary record.

### Address Formatting
```pascal
procedure writeMACAddress(mac: TMACAddress);
procedure writeMACAddressEx(mac: TMACAddress);
procedure writeIPv4Address(ip: TIPv4Address);
procedure writeIPv4AddressEx(ip: TIPv4Address);
```
Writes a formatted address string to the system log. The `Ex` variants omit the trailing newline.

### Packet Context Management
```pascal
function newPacketContext: PPacketContext;
procedure freePacketContext(ctx: PPacketContext);
```
Allocates or frees a `TPacketContext` on the kernel heap.

### Checksum
```pascal
function calculateChecksum(data: pointer; length: uint32): uint16;
function verifyChecksum(data: pointer; length: uint32): boolean;
```
Computes an RFC 1071 one's complement Internet checksum over `length` bytes. `verifyChecksum` returns `true` if the checksum over the data (including the checksum field) equals zero.

### Routing Helpers
```pascal
function sameSubnetIPv4(a, b: TIPv4Address; mask: TIPv4Address): boolean;
```
Returns `true` if addresses `a` and `b` are on the same subnet given `mask`.

### Context Swap Helpers
```pascal
procedure contextMACSwitch(ctx: PPacketContext);
procedure contextIPv4Switch(ctx: PPacketContext);
```
Swaps source and destination MAC or IPv4 addresses within the packet context. Used by protocol layers when constructing replies.
