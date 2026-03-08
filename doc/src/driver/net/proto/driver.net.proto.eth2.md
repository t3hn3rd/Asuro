# driver.net.proto.eth2

Ethernet II (DIX) framing layer.

## Overview

This unit implements Ethernet II frame encapsulation and de-multiplexing. It maintains a 65536-entry dispatch table indexed by EtherType for exclusive per-protocol receive handlers, and a parallel boolean array for promiscuous handlers that receive all frames regardless of EtherType or destination. On transmit, it prepends the Ethernet header and pads short payloads to the minimum Ethernet frame size.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `syslog`

## Functions and Procedures

### register
```pascal
procedure register;
```
Initialises the dispatch table and registers itself as the layer-2 receive handler via `driver.net.registerNextLayer`.

### registerType
```pascal
procedure registerType(ethertype: uint16; callback: TRecvCallback);
```
Registers an exclusive receive handler for the given EtherType. Only one handler per EtherType is supported; subsequent registrations replace the previous entry.

### registerTypePromisc
```pascal
procedure registerTypePromisc(ethertype: uint16; callback: TRecvCallback);
```
Registers a promiscuous receive handler. The handler receives every incoming frame, regardless of the destination MAC or whether another handler is registered for the same EtherType.

### send
```pascal
procedure send(dst_mac: TMACAddress; ethertype: uint16; data: pointer; length: uint32);
```
Constructs a `TEthernetHeader` with the destination MAC, the local MAC from `driver.net.getMAC` as source, and the given EtherType. Pads the payload to a minimum of 46 bytes if necessary, then calls `driver.net.send`.

### recv
```pascal
procedure recv(ctx: PPacketContext);
```
Called by `driver.net` for each received frame. Parses the `TEthernetHeader` from the frame, fills `ctx.src_mac`, `ctx.dst_mac`, and `ctx.protocol`. Discards unicast frames not addressed to the local MAC (broadcast and promiscuous frames are always passed through). Dispatches to the registered EtherType handler and to all promiscuous handlers.

## Notes

- The dispatch table occupies 65536 pointer entries; entries for unregistered EtherTypes are `nil`.
- Promiscuous handlers are notified after the regular EtherType handler.
- Minimum Ethernet frame payload is 46 bytes (to achieve the 64-byte minimum frame size including header and CRC); padding is zero-filled.
