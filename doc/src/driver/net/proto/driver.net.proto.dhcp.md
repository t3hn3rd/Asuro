# driver.net.proto.dhcp

DHCP client implementation (RFC 2131/2132).

## Overview

This unit implements a DHCP client. It builds and transmits DHCP messages over UDP (client port 68, server port 67), parses DHCP option fields in responses, and applies the obtained IP configuration to `driver.net.proto.ipv4`. The unit supports the DISCOVER → OFFER → REQUEST → ACK exchange.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.eth2`
- `driver.net.proto.ipv4`
- `driver.net.proto.udp`
- `syslog`

## Types

### TDHCPOption
Represents a single DHCP option field for construction of outgoing messages:

| Field | Type | Description |
|---|---|---|
| `opcode` | `TDHCPOpCode` | RFC 2132 option tag |
| `size` | `uint8` | Data length in bytes |
| `value` | `uint32` | Option value (integer) |
| `bigendian` | `boolean` | Whether `value` should be byte-swapped before transmission |

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers a UDP receive callback on port 68 for incoming DHCP server messages.

### DHCPDiscover
```pascal
procedure DHCPDiscover;
```
Initiates a DHCP negotiation:
1. Sends a DHCPDISCOVER broadcast with a random transaction ID.
2. Waits for a DHCPOFFER reply on port 68.
3. Sends a DHCPREQUEST for the offered IP.
4. Waits for a DHCPACK.
5. Calls `driver.net.proto.ipv4` to apply the obtained IP, gateway, and subnet mask.

### nullConfiguration
```pascal
procedure nullConfiguration(var opts: array of TDHCPOption);
```
Zeroes an options array before populating it for a new message.

### createHeader
```pascal
function createHeader(op: uint8; xid: uint32): TDHCPHeader;
```
Builds a `TDHCPHeader` with hardware type `$01` (Ethernet), hardware length 6, the current MAC address from `driver.net.getMAC`, and the given transaction ID.

## Notes

- DHCP messages are broadcast at the Ethernet level (destination `FF:FF:FF:FF:FF:FF`) until an IP address is assigned.
- The `DHCP_MAGIC` cookie (`$63825363`) is written at offset 236 of the message before appending option TLVs.
- Only a minimal set of requested options is sent in the parameter request list: subnet mask, router (gateway), DNS server, and domain name.
