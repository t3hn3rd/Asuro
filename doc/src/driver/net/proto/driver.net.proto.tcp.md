# driver.net.proto.tcp

TCP (Transmission Control Protocol) implementation.

## Overview

This unit implements a full TCP stack (RFC 793) with Jacobson/Karels RTT estimation, Nagle algorithm, congestion control, keep-alive, zero-window probing, and delayed acknowledgements. The implementation is connection-oriented and supports both active (client) and passive (server) modes. Connections are represented by `TTCPSocket` handles backed by `TTCB` control blocks.

## Dependencies

- `driver.net`
- `driver.net.types`
- `driver.net.util`
- `driver.net.proto.eth2`
- `driver.net.proto.arp`
- `driver.net.proto.ipv4`
- `syslog`
- `terminal`

## Constants

### Protocol Constants
- `TCP_PROTOCOL_ID`: `$06`
- `TCP_DEFAULT_MSS`: `1460` bytes
- `TCP_DEFAULT_WINDOW`: `8192` bytes
- `TCP_MAX_RETRANSMISSIONS`: `5`

### Timing Constants (in kernel ticks)
- `TCP_RETRANS_TICKS`: `1024`
- `TCP_TIMEWAIT_TICKS`: `61440` (approx 2× MSL)
- `TCP_SYN_RETRANS_TICKS`: `3072`
- `TCP_DELAYED_ACK_TICKS`: `205`
- `TCP_KEEPALIVE_TICKS`, `TCP_KEEPALIVE_INTVL_TICKS`, `TCP_ZWP_TICKS`

### TCP Flag Bits
`TCP_FLAG_FIN` (`$01`), `TCP_FLAG_SYN` (`$02`), `TCP_FLAG_RST` (`$04`), `TCP_FLAG_PSH` (`$08`), `TCP_FLAG_ACK` (`$10`), `TCP_FLAG_URG` (`$20`).

## Functions and Procedures

### register
```pascal
procedure register;
```
Registers TCP as the handler for IPv4 protocol `$06`.

### connect
```pascal
function connect(dst_ip: TIPv4Address; dst_port: uint16; OnRecv: TTCPReceiveCallback; OnEvent: TTCPEventCallback): PTCPSocket;
```
Initiates an active TCP connection. Allocates a TCB, selects an ephemeral source port, sends SYN, and transitions to `tsTCPSynSent`. Returns a socket handle.

### listen
```pascal
function listen(port: uint16; OnRecv: TTCPReceiveCallback; OnEvent: TTCPEventCallback): PTCPSocket;
```
Creates a passive listening socket on the given port. Transitions to `tsTCPListen`.

### accept
```pascal
function accept(listener: PTCPSocket): PTCPSocket;
```
Returns the next completed incoming connection from the listener's accept queue, or `nil` if none are ready.

### send
```pascal
function send(socket: PTCPSocket; data: pointer; length: uint32): uint32;
```
Copies data into the socket's send buffer. The Nagle algorithm controls when segments are actually transmitted. Returns the number of bytes accepted into the buffer.

### close
```pascal
procedure close(socket: PTCPSocket);
```
Initiates an orderly close by sending FIN and transitioning through the FIN_WAIT or CLOSE_WAIT states.

### abort_connection
```pascal
procedure abort_connection(socket: PTCPSocket);
```
Sends RST and immediately frees the TCB, without waiting for the remote to acknowledge.

### recv (internal)
Dispatched by IPv4. Parses the TCP header, validates checksum using the pseudo-header, and drives the state machine. Delivers in-order data to the `OnRecv` callback. Out-of-order segments are queued in the TCB's OOO list.

### tick (called by kernel timer)
Advances all active TCP timers: retransmission, TIME_WAIT, delayed ACK, keep-alive, and zero-window probe.

## Notes

- RTT estimation uses the Jacobson/Karels algorithm: SRTT and RTTVAR are updated per ACK, and RTO is clamped between 200 ms and 120 s.
- Congestion control implements slow start and congestion avoidance; `ssthresh` is halved on timeout.
- The Nagle algorithm buffers small writes until either a full MSS segment is available or all outstanding data has been acknowledged.
