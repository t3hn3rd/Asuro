# driver.net.proto.icmp

ICMP (Internet Control Message Protocol) echo request/reply implementation.

## Overview

This unit implements ICMP over IPv4 (protocol `$01`). It supports sending echo requests (type 8) and receiving echo replies (type 0). Up to 256 concurrent pending echo requests are tracked by identifier, each with an optional reply callback and error callback. Incoming echo requests are answered automatically.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.eth2`
- `driver.net.proto.arp`
- `driver.net.proto.ipv4`
- `syslog`

## Types

### TICMPHandler
Per-request state tracking:

| Field | Type | Description |
|---|---|---|
| `identifier` | `uint16` | ICMP identifier field for this request |
| `OnReply` | `procedure(ctx: PPacketContext)` | Called when a matching echo reply arrives |
| `OnError` | `procedure(code: uint32)` | Called on routing or resolution failure |
| `active` | `boolean` | Whether this slot is in use |

### Error Codes
`aecFailedToResolveHost`, `aecNoRouteToHost` — passed to the `OnError` callback.

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers ICMP as the handler for IPv4 protocol `$01` via `driver.net.proto.ipv4.registerProtocol`.

### sendICMPRequest
```pascal
procedure sendICMPRequest(dst_ip: TIPv4Address; identifier, sequence: uint16; OnReply: TICMPReplyCallback; OnError: TICMPErrorCallback);
```
Sends an ICMP echo request to `dst_ip`:
1. Determines whether the destination is on the local subnet; if so, resolves the destination MAC via ARP; otherwise uses the gateway MAC.
2. Calls `OnError(aecFailedToResolveHost)` or `OnError(aecNoRouteToHost)` if resolution fails.
3. Builds the ICMP header with `ICMP_DATA_GENERIC` payload, computes checksum, and sends via IPv4.
4. Registers the handler slot in `Handlers[identifier]`.

### recv
```pascal
procedure recv(ctx: PPacketContext);
```
Dispatched by IPv4 for all incoming ICMP packets. Handles:
- **Type 8 (echo request)**: Swaps source and destination IP/MAC from the context and sends a type-0 echo reply.
- **Type 0 (echo reply)**: Looks up `Handlers[identifier]`, calls the registered `OnReply` callback, and clears the slot.

## Notes

- Each outstanding request occupies one of 256 slots indexed by the ICMP identifier field. Identifiers above 255 are not tracked.
- ICMP data uses the `ICMP_DATA_GENERIC` constant payload defined in `driver.net.types`.
