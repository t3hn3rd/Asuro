# driver.net.proto.arp

ARP (Address Resolution Protocol) implementation with cache.

## Overview

This unit implements ARP over Ethernet (hardware type `$0001`, protocol type `$0800`). It maintains an in-memory ARP cache as a linked list, handles incoming ARP requests and replies, generates outgoing requests and gratuitous announcements, and provides IP-to-MAC resolution for use by higher protocol layers.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.eth2`
- `syslog`
- `terminal`

## Types

### TARPCacheRecord
Linked-list node in the ARP cache:

| Field | Type | Description |
|---|---|---|
| `mac` | `TMACAddress` | Resolved MAC address |
| `ip` | `TIPv4Address` | Corresponding IP address |
| `Next` | `^TARPCacheRecord` | Next cache entry, or `nil` |

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers ARP as a promiscuous handler for EtherType `$0806` via `driver.net.proto.eth2.registerTypePromisc`.

### recv
```pascal
procedure recv(ctx: PPacketContext);
```
Processes an incoming ARP frame. Updates the cache with the sender's MAC/IP pair. If the ARP operation is a request targeting our IPv4 address, constructs and sends a reply.

### send
```pascal
procedure send(op: uint16; target_mac: TMACAddress; target_ip: TIPv4Address);
```
Builds a `TARPHeader` and transmits it via `driver.net.proto.eth2.send` to the specified destination.

### sendGratuitous
```pascal
procedure sendGratuitous;
```
Sends a gratuitous ARP announcement (operation=reply, target=our own IP) to the broadcast MAC. Used to update other hosts' caches after IP configuration changes.

### sendRequest
```pascal
procedure sendRequest(target_ip: TIPv4Address);
```
Sends an ARP request asking who owns `target_ip`.

### sendRequestGateway
```pascal
procedure sendRequestGateway;
```
Convenience wrapper that sends an ARP request for the configured default gateway IP.

### resolveIP
```pascal
function resolveIP(ip: TIPv4Address; out mac: TMACAddress): boolean;
```
Looks up `ip` in the cache. Returns `true` and fills `mac` on a hit. On a miss, sends an ARP request and returns `false`; the caller must retry after allowing time for a reply.

### IPv4ToMAC
```pascal
function IPv4ToMAC(ip: TIPv4Address): TMACAddress;
```
Cache lookup returning the MAC for the given IP, or `NULL_MAC` if not found.

### MACToIIPv4
```pascal
function MACToIIPv4(mac: TMACAddress): TIPv4Address;
```
Reverse cache lookup returning the IP for the given MAC, or `NULL_IP` if not found.

### terminal_command_arp
```pascal
procedure terminal_command_arp(args: string);
```
Terminal command handler. With no arguments, dumps the full ARP cache. With an IP address argument, sends an ARP request for that IP.

## Notes

- The cache is an unbounded singly-linked list; entries are never expired in this implementation.
- ARP replies to requests are sent with the sender and target fields swapped from the incoming request.
