# driver.net.proto.udp

UDP (User Datagram Protocol) implementation.

## Overview

This unit implements UDP over IPv4 (protocol `$11`). It maintains a 65536-entry port binding table and provides send, bind, and unbind operations. Incoming datagrams are dispatched to the callback registered for the destination port. Checksum calculation uses the standard IPv4 UDP pseudo-header.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.ipv4`
- `syslog`

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers UDP as the handler for IPv4 protocol `$11` via `driver.net.proto.ipv4.registerProtocol`.

### bind
```pascal
procedure bind(port: uint16; callback: TUDPRecieveCallback);
```
Registers `callback` as the receive handler for the given UDP port. Replaces any existing binding.

### unbind
```pascal
procedure unbind(port: uint16);
```
Clears the receive handler for the given port.

### send
```pascal
procedure send(dst_ip: TIPv4Address; src_port, dst_port: uint16; data: pointer; length: uint32);
```
Builds a `TUDPHeader`, computes the checksum using `CalculateChecksum` with the pseudo-header, and transmits via `driver.net.proto.ipv4.send` with TTL 64.

### recv (internal)
Dispatched by IPv4. Parses the `TUDPHeader` and calls the callback registered in `Ports[dst_port]`. Frames arriving on unbound ports are silently dropped.

### CalculateChecksum (internal)
Computes the UDP checksum over the pseudo-header (source IP, destination IP, protocol `$11`, UDP length) and the UDP header plus data, with appropriate endian swapping.

## Notes

- The `Ports` array holds one callback pointer per port number (0–65535). Concurrent bindings on the same port are not supported.
- A checksum of zero in the received header disables checksum verification for that datagram (permitted by RFC 768).
