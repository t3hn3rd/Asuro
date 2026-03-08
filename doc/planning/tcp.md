# TCP Implementation Plan

## Overview
Implement TCP (Transmission Control Protocol, RFC 793) for the Asuro kernel network stack. TCP sits at L4 alongside UDP and ICMP, registers with IPv4 as protocol `0x06`, and provides reliable, ordered, byte-stream delivery.

## Design Decisions
| Decision | Choice | Rationale |
|---|---|---|
| API Style | Callback-based (like UDP) | Matches existing async/interrupt-driven architecture |
| Timer Source | 1024 Hz TMR_0_ISR hook | Sub-millisecond granularity; hookable via `TMR_0_ISR.hook()` |
| Receive Window | 8192 bytes (fixed) | Medium; good balance of throughput vs memory |
| Default MSS | 1460 bytes | Standard Ethernet (1500 MTU - 20 IP - 20 TCP) |
| Connection Tracking | Dynamic list (DList) of dynamically allocated TCBs | Up to 65535 connections; contiguous memory, better cache locality |
| ISN Generation | `rand32()` | Seeded from RTC at boot |

## Architecture

### Layer Position
```
L5: DHCP (uses UDP)
L4: TCP  /  UDP  /  ICMP     <-- tcp.pas lives here
L3: IPv4 / ARP
L2: Ethernet II
L1: NIC (E1000)
```

### Packet Flow
**Send:** `tcp.send()` → build TCP header → `ipv4.send(buffer, size, context)` with `Protocol.L4 := $06`
**Recv:** `ipv4` dispatches protocol `$06` → `tcp.ProcessPacket()` → lookup TCB → state machine → user callback

### Connection State (TCB - Transmission Control Block)
Each connection is identified by a 4-tuple: `(local_ip, local_port, remote_ip, remote_port)`.

```
TTCPState = (
    tssClosed, tssListen, tssSynSent, tssSynReceived,
    tssEstablished, tssFinWait1, tssFinWait2, tssCloseWait,
    tssClosing, tssLastAck, tssTimeWait
);
```

### Key Data Structures (in nettypes.pas)
- `TTCPHeader` - 20-byte TCP header (packed/bitpacked)
- `TTCPState` - Connection state enum
- `TTCB` / `PTCB` - Transmission Control Block (per-connection state)
- `TTCPSocket` / `PTCPSocket` - User-facing socket handle
- `TTCPError` - Error codes enum
- `TTCPReceiveCallback` - `procedure(socket: PTCPSocket; data: void; len: uint16)`
- `TTCPEventCallback` - `procedure(socket: PTCPSocket; event: TTCPEvent)`

### Public API (tcp.pas)
```pascal
procedure register();                                           // Init + register with IPv4
function  connect(context: PTCPConnectContext): PTCPSocket;     // Active OPEN
function  listen(context: PTCPListenContext): PTCPSocket;       // Passive OPEN
function  accept(listener: PTCPSocket): PTCPSocket;             // Accept incoming (from listen)
function  send(socket: PTCPSocket; data: void; len: uint16): TTCPError;  // Send data
function  close(socket: PTCPSocket): TTCPError;                 // Initiate graceful close
function  abort_connection(socket: PTCPSocket): TTCPError;      // Send RST, force close
```

## TCP State Machine (RFC 793)
```
                              +---------+ ---------\      active OPEN
                              |  CLOSED |            \    -----------
                              +---------+<---------\   \   create TCB
                                |     ^              \   \  snd SYN
                   passive OPEN |     |   CLOSE        \   \
                   ------------ |     | ----------       \   \
                    create TCB  |     | delete TCB         \   \
                                V     |                      \   V
                              +---------+            +---------+
                              |  LISTEN |            | SYN     |
                              +---------+            | SENT    |
                   rcv SYN      |     |     CLOSE    +---------+
                  -----------   |     |    -------       |     |
                  snd SYN,ACK  /      |   delete TCB     |     |
                              /       |                  |     |
                             V        |   rcv SYN,ACK    |     |
                       +---------+    |   -----------    |     |
                       |SYN RCVD |    |   snd ACK       |     |
                       +---------+    |                  |     |
                 rcv ACK  |     |     |                  |     |
                 -------  |     |     V                  |     |
                  xxx     |     | +---------+   rcv ACK  |     |
                          |     | |  ESTAB  |<-----------+     |
                          |     | +---------+                  |
```

## Implementation Phases

### Phase 1: Core Protocol Engine _(complete)_
- [x] Planning & design (this document)
- [x] TCP types in `nettypes.pas` (header, TCB, state enum, error codes, callbacks)
- [x] `tcp.pas` skeleton with registration
- [x] TCP header construction & checksum (pseudo-header based, like UDP)
- [x] TCB management (create, find by 4-tuple, destroy)
- [x] State machine: CLOSED → SYN_SENT → ESTABLISHED (active OPEN / 3-way handshake)
- [x] State machine: ESTABLISHED → data transfer with ACK
- [x] State machine: FIN_WAIT_1 → FIN_WAIT_2 → TIME_WAIT → CLOSED (active CLOSE)
- [x] State machine: CLOSE_WAIT → LAST_ACK → CLOSED (passive CLOSE)
- [x] Retransmission timer (1024 Hz hook, simple fixed timeout)
- [x] RST handling (send & receive)
- [x] Sequence number management (SND.UNA, SND.NXT, RCV.NXT)
- [x] Receive window management (fixed 8192 bytes)
- [x] Compilation verification

### Phase 2: Server Support (listen/accept) _(complete)_
- [x] State machine: LISTEN → SYN_RECEIVED → ESTABLISHED (passive OPEN)
- [x] Listen backlog queue (BacklogMax enforcement, CountPendingForPort)
- [x] Accept mechanism (accept() returns first ESTABLISHED child socket)
- [x] Per-port listen binding (FindListenTCB)
- [x] Integration test: respond to incoming SYN

### Phase 3: Robustness & Hardening _(complete)_
- [x] Delayed ACK timer (~200ms, TCP_DELAYED_ACK_TICKS)
- [x] Nagle's algorithm (buffer small sends while unACKed data outstanding, flush on ACK)
- [x] RTT estimation (Jacobson/Karels) for adaptive retransmission timeout
- [x] Congestion control (slow start, congestion avoidance, SSThresh/CongWnd)
- [x] Zero-window probing (exponential backoff, send 1-byte probes)
- [x] MSS option negotiation in SYN/SYN-ACK (Kind=2, Len=4)
- [x] Keep-alive timer (30s idle, 10s interval, 5 probes max)
- [x] Out-of-order segment reassembly (4-slot buffer, FlushOOOSegments)
- [x] TIME_WAIT timer (2*MSL = 60s)

### Phase 4: Terminal Integration & Testing _(complete)_
- [x] `tcpconnect` terminal command for manual testing
- [x] `tcplisten` terminal command for passive testing
- [x] Syslog integration for connection lifecycle tracing
- [x] `tcphttp` command for HTTP GET requests (higher-level protocol integration)

## Memory Management Strategy
- All TCBs allocated via `kalloc()`, freed via `kfree()` on connection close
- Send/receive buffers allocated per-TCB (8192 bytes each) via `kalloc()`
- Temporary packet buffers for TX allocated per-send, freed after `ipv4.send()`
- No static arrays for connection tracking; DList of TCB pointers searched by 4-tuple

## Retransmission Strategy
- **Phase 1:** Fixed retransmission timeout: 1 second (1024 timer ticks), used as initial RTO
- **Phase 3:** Adaptive RTO via Jacobson/Karels RTT estimation (SRTT scaled ×8, RTTVAR scaled ×4)
  - RTO = SRTT/8 + max(1, RTTVAR), clamped to [1s, 60s]
  - Karn's algorithm: RTT not measured on retransmitted segments
- Max retransmission attempts: 5
- Timer checked on each 1024 Hz tick; only active connections scanned
- SYN retransmission: same timeout, 5 attempts
- On timeout: SSThresh = CongWnd/2, CongWnd = 1×MSS (congestion response)
- Exponential backoff: RTO doubles on each retransmission

## Files Modified
| File | Changes |
|---|---|
| `src/driver/net/include/nettypes.pas` | TCP types, header, TCB (with Phase 3 fields), OOO entry type, enums, callbacks |
| `src/driver/net/l4/tcp.pas` | Full TCP implementation (all 4 phases) |
| `src/driver/net/l1/net.pas` | Add `tcp.register` call in `init` |

## Testing Strategy
1. **Compile test** - Ensure clean build with no errors
2. **Serial log** - Monitor SYN/ACK handshake via syslog output on serial
3. **External tool** - Use netcat/ncat on host to accept connections from VM
4. **Packet capture** - Wireshark on host-only adapter to verify wire format
