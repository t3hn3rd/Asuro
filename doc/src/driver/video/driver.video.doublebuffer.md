# driver.video.doublebuffer

Double-buffered rendering using SSE-accelerated memory copy.

## Overview

This unit implements double-buffered rendering for the video subsystem. It allocates a back buffer in kernel memory, redirects drawing operations to the back buffer, and provides a `Flush` procedure that copies the completed back buffer to the front (visible) framebuffer using SSE 128-bit memory copy instructions for maximum throughput.

## Dependencies

- `driver.video`
- `driver.video.types`
- `core.memory`
- `core.sse`
- `syslog`

## Constants

### COPY_WIDTH
Value: `128`. The SSE copy granularity in bits (16 bytes per operation), used by the `__SSE_128_memcpy` routine.

## Functions and Procedures

### allocateBackBuffer
```pascal
function allocateBackBuffer(size: uint32): pointer;
```
Allocates a physically contiguous back buffer of `size` bytes using `klalloc` (large kernel allocation). Returns the base address, or `nil` on failure.

### initBackBuffer
```pascal
procedure initBackBuffer(VideoInterface: PVideoInterface);
```
Allocates a back buffer matching the front buffer's dimensions and BPP, fills in `VideoInterface^.BackBuffer`, and sets `VideoInterface^.DefaultBuffer` to point at the back buffer.

### Flush
```pascal
procedure Flush(Front, Back: PVideoBuffer);
```
Copies the entire back buffer to the front buffer using `__SSE_128_memcpy` in 128-bit (16-byte) chunks. The buffer size must be a multiple of 16 bytes; the framebuffer dimensions are chosen to satisfy this requirement.

### enable
```pascal
procedure enable(VideoInterface: PVideoInterface);
```
Calls `initBackBuffer`, then replaces `VideoInterface^.DrawRoutines.Flush` with `@Flush`. Registered as the `'BASIC_DOUBLE_BUFFER'` driver in `driver.video`.

## Notes

- `klalloc` is used rather than the standard kernel allocator because the back buffer may be several megabytes; this requires a large contiguous allocation that the slab allocator cannot satisfy.
- The SSE copy path requires the source and destination addresses to be 16-byte aligned; `klalloc` returns suitably aligned memory.
