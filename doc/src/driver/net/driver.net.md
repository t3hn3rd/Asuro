# driver.net

Layer-1 network interface and protocol stack initialisation.

## Overview

This unit is the base of the Asuro network stack. It holds the registered transmit and receive callbacks for the single active network interface card, dispatches outgoing frames to the NIC, and passes incoming frames to the registered layer-2 handler. It also initialises all higher protocol layers and provides timestamped logging helpers.

## Dependencies

- `driver.net.types`
- `driver.net.proto.eth2`
- `driver.net.proto.arp`
- `driver.net.proto.ipv4`
- `driver.net.proto.icmp`
- `driver.net.proto.tcp`
- `driver.net.proto.udp`
- `driver.net.proto.dhcp`
- `driver.timer.rtc`
- `syslog`

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises all protocol layers in order: ETH2, ARP, IPv4, ICMP, TCP, UDP, DHCP. Must be called once during system startup before any network operation.

### registerNetworkCard
```pascal
procedure registerNetworkCard(SendCallback: TNetSendCallback; MAC: TMACAddress);
```
Registers the first NIC that calls in. Stores the send callback and the hardware MAC address. Only the first call has effect; subsequent calls are ignored.

### registerNextLayer
```pascal
procedure registerNextLayer(RecvCallback: TRecvCallback);
```
Registers the layer-2 receive handler. Called by `driver.net.proto.eth2` during its initialisation.

### send
```pascal
procedure send(data: pointer; length: uint32);
```
Passes a raw frame to the registered NIC send callback.

### recv
```pascal
procedure recv(data: pointer; length: uint32);
```
Called by the NIC driver when a frame arrives. Allocates a `TPacketContext`, fills the data pointer and length, calls the registered `NextLayer` receive callback, then frees the context.

### getMAC
```pascal
function getMAC: TMACAddress;
```
Returns the MAC address of the registered NIC.

### isRegistered
```pascal
function isRegistered: boolean;
```
Returns `true` if a NIC has been registered via `registerNetworkCard`.

### writeToLog / writeToLogLn
```pascal
procedure writeToLog(msg: string);
procedure writeToLogLn(msg: string);
```
Writes a message to the system log prefixed with the current RTC timestamp (HH:MM:SS format). `writeToLogLn` appends a newline.

## Notes

- The network stack supports only a single active NIC at a time. Multiple NIC registrations are silently discarded.
- `TPacketContext` is allocated on the heap for each received frame and freed after the receive chain returns; protocol handlers must not retain pointers to the context.
