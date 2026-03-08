# driver.net.proto.ipv4

IPv4 packet handling and protocol dispatch.

## Overview

This unit implements IPv4 over Ethernet II. It maintains the system IPv4 configuration (address, gateway, netmask, UP state) and provides transmit, receive, and protocol registration functions. On transmit, it builds a standard IPv4 header with incrementing packet IDs and computes the header checksum. On receive, it parses the header and dispatches to the registered layer-4 protocol handler.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.eth2`
- `driver.net.proto.arp`
- `syslog`
- `terminal`

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers IPv4 as the exclusive handler for EtherType `$0800` via `driver.net.proto.eth2.registerType`.

### registerProtocol
```pascal
procedure registerProtocol(protocol: uint8; callback: TRecvCallback);
```
Registers a layer-4 protocol handler (e.g. ICMP=`$01`, TCP=`$06`, UDP=`$11`) that receives the packet context after the IPv4 header is stripped.

### send
```pascal
procedure send(dst_ip: TIPv4Address; protocol: uint8; data: pointer; length: uint32; ttl: uint8);
```
Builds a `TIPV4Header` (version=4, IHL=5, TTL from argument, incrementing `CurrentID`), computes the header checksum, and sends via `driver.net.proto.eth2.send` using the ARP-resolved destination MAC.

### recv
```pascal
procedure recv(ctx: PPacketContext);
```
Called by ETH2 for EtherType `$0800` frames. Parses the IPv4 header into `ctx`, validates the header checksum, fills `ctx.src_ip` and `ctx.dst_ip`, and dispatches to the registered handler for `ctx.protocol`.

### getIPv4Config
```pascal
function getIPv4Config: PIPv4Configuration;
```
Returns a pointer to the global `Config` record. Used by other protocol units to read the local IP address, gateway, and netmask.

### setIPv4Config
```pascal
procedure setIPv4Config(ip, gateway, netmask: TIPv4Address);
```
Updates the global configuration and marks the interface as UP.

### terminal_command_ifconfig
```pascal
procedure terminal_command_ifconfig(args: string);
```
Terminal command to display or configure the IPv4 interface. With no arguments, prints current configuration. With arguments `ip gateway netmask`, calls `setIPv4Config`.

## Notes

- IPv4 fragmentation and reassembly are not implemented; frames that arrive fragmented are discarded.
- `CurrentID` is a module-level counter incremented for each outgoing packet.
- Packets not addressed to the local IP or broadcast IP are silently dropped.
