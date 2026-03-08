# driver.net.types

Core network data types, protocol headers, and callback signatures.

## Overview

This unit defines all shared types for the Asuro network stack: fundamental address types, packet context, protocol header records, TCP state machine types, DHCP structures, and callback type definitions. All network protocol units depend on this unit.

## Dependencies

- (none — foundational network unit)

## Constants

### Address Constants
- `BROADCAST_MAC`: `FF:FF:FF:FF:FF:FF`
- `NULL_MAC`: `00:00:00:00:00:00`
- `BROADCAST_IP`: `255.255.255.255`
- `NULL_IP`: `0.0.0.0`

### DHCP
- `DHCP_MAGIC`: `$63825363` — RFC 2132 magic cookie value

### ICMP
- `ICMP_DATA_GENERIC`: Default 56-byte ICMP echo request payload

## Types

### TMACAddress
`array[0..5] of uint8`. A 6-byte Ethernet MAC address.

### TIPv4Address
`array[0..3] of uint8`. A 4-byte IPv4 address.

### TMACPair / TIPv4Pair
Source and destination address pairs used during packet construction.

### TProtocol
`uint16`. An EtherType or IP protocol number.

### TPacketContext
Per-frame context passed through the receive chain:

| Field | Type | Description |
|---|---|---|
| `data` | `pointer` | Pointer to raw frame data |
| `length` | `uint32` | Frame length in bytes |
| `src_mac` | `TMACAddress` | Source MAC (filled by ETH2 layer) |
| `dst_mac` | `TMACAddress` | Destination MAC |
| `src_ip` | `TIPv4Address` | Source IP (filled by IPv4 layer) |
| `dst_ip` | `TIPv4Address` | Destination IP |
| `protocol` | `TProtocol` | EtherType or IP protocol |

### TIPv4Configuration
Holds the active IPv4 configuration: `ip`, `gateway`, `netmask` (all `TIPv4Address`), and `up: boolean`.

### Protocol Headers (bitpacked records)
- `TICMPHeader`: `type_`, `code`, `checksum`, `identifier`, `sequence`
- `TARPAbstractHeader` / `TARPHeader`: hardware type, protocol, address lengths, opcode, sender/target MAC and IP
- `TEthernetHeader`: destination and source MAC, EtherType
- `TIPV4Header`: version/IHL (4-bit fields), DSCP/ECN, total length, ID, flags/fragment offset, TTL, protocol, checksum, source and destination IP
- `TUDPHeader`: source port, destination port, length, checksum
- `TTCPHeader`: source/destination port, sequence/acknowledgement numbers, data offset/flags, window, checksum, urgent pointer
- `TTCPPseudoHeader`: source/destination IP, zero byte, protocol, TCP length (for checksum calculation)

### TCP State Machine

#### TTCPState
Eleven-value enumeration: `tsTCPClosed`, `tsTCPListen`, `tsTCPSynSent`, `tsTCPSynReceived`, `tsTCPEstablished`, `tsTCPFinWait1`, `tsTCPFinWait2`, `tsTCPCloseWait`, `tsTCPClosing`, `tsTCPLastAck`, `tsTCPTimeWait`.

#### TTCPEvent
Events that drive state transitions: `teConnect`, `teListen`, `teRecvSyn`, `teRecvSynAck`, `teRecvAck`, `teRecvFin`, `teRecvRst`, `teClose`, `teTimeout`.

#### TTCPSocket / TTCB
`TTCPSocket` is the public handle returned to application code. `TTCB` (Transmission Control Block) holds full connection state including:
- Sequence/acknowledgement numbers (`SND_UNA`, `SND_NXT`, `RCV_NXT`, `RCV_WND`)
- Send/receive ring buffers
- Nagle algorithm state and pending data
- RTT estimation variables (Jacobson/Karels: `SRTT`, `RTTVAR`, `RTO`)
- Congestion control (`cwnd`, `ssthresh`, `ca_state`)
- Keep-alive timer and zero-window probe state
- Out-of-order segment list

### DHCP Types

#### TDHCPHeader
Fixed 236-byte DHCP header with fields: `op`, `htype`, `hlen`, `hops`, `xid`, `secs`, `flags`, `ciaddr`, `yiaddr`, `siaddr`, `giaddr`, `chaddr`, `sname`, `file`.

#### TDHCPOpCode
Full RFC 2132 DHCP option enumeration (subnet mask, router, DNS, hostname, domain, broadcast address, lease time, message type, server identifier, parameter request list, message, max DHCP size, renewal time, rebinding time, vendor class, client identifier, etc.).

#### TDHCPMessageType
`DHCPDISCOVER`, `DHCPOFFER`, `DHCPREQUEST`, `DHCPACK`, `DHCPNAK`, `DHCPRELEASE`, `DHCPINFORM`.

### Callback Types

| Type | Signature | Description |
|---|---|---|
| `TNetSendCallback` | `procedure(data: pointer; len: uint32)` | NIC transmit callback |
| `TRecvCallback` | `procedure(ctx: PPacketContext)` | Layer receive callback |
| `TUDPRecieveCallback` | `procedure(ctx: PPacketContext; src_port, dst_port: uint16)` | UDP receive handler |
| `TTCPReceiveCallback` | `procedure(socket: PTCPSocket; data: pointer; len: uint32)` | TCP data received |
| `TTCPEventCallback` | `procedure(socket: PTCPSocket; event: TTCPEvent)` | TCP state change notification |
