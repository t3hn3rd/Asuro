# driver.video.types

Shared video subsystem data types and function pointer signatures.

## Overview

This unit defines all foundational types for the video subsystem. It is depended upon by every video driver and the front-end `driver.video` unit. No executable code is present; the unit consists entirely of type and constant declarations.

## Dependencies

- (none — foundational video unit)

## Types

### VideoBuffer
```pascal
VideoBuffer = uint32;
```
A raw physical or virtual framebuffer address treated as an opaque 32-bit value.

### TVideoBuffer
Describes a single framebuffer (front or back):

| Field | Type | Description |
|---|---|---|
| `Initialized` | `boolean` | Whether this buffer has been configured |
| `Location` | `pointer` | Base address of the framebuffer |
| `BitsPerPixel` | `uint8` | Colour depth (8, 16, 24, or 32) |
| `Width` | `uint32` | Horizontal resolution in pixels |
| `Height` | `uint32` | Vertical resolution in pixels |

### Function Pointer Types

| Type | Signature | Description |
|---|---|---|
| `FDrawPixel` | `procedure(Buffer: PVideoBuffer; X, Y: uint32; Pixel: TRGB32)` | Draw a single pixel |
| `FFlush` | `procedure(Front, Back: PVideoBuffer)` | Copy back buffer to front buffer |
| `FDrawLine` | `procedure(Buffer: PVideoBuffer; X1, Y1, X2, Y2: uint32; Pixel: TRGB32)` | Draw a line |
| `FDrawRect` | `procedure(Buffer: PVideoBuffer; X, Y, W, H: uint32; Pixel: TRGB32)` | Draw a rectangle outline |
| `FFillRect` | `procedure(Buffer: PVideoBuffer; X, Y, W, H: uint32; Pixel: TRGB32)` | Fill a rectangle |

### TDrawRoutines
Groups all drawing function pointers into a single record. An instance of this record is embedded in `TVideoInterface` and populated by the active BPP-specific driver module during `init`.

### TVideoInterface
The central video state record:

| Field | Type | Description |
|---|---|---|
| `DefaultBuffer` | `PVideoBuffer` | Active draw target (points to back buffer when double buffering is enabled) |
| `FrontBuffer` | `TVideoBuffer` | The visible (front) framebuffer |
| `BackBuffer` | `TVideoBuffer` | The off-screen (back) framebuffer |
| `DrawRoutines` | `TDrawRoutines` | Currently active drawing function pointers |

### Callback Types

| Type | Description |
|---|---|
| `FEnableDriver` | Called when a named video driver is enabled; receives `PVideoInterface` |
| `FRegisterDriver` | Registers a driver identifier and its enable callback |
| `FInitDriver` | Driver initialisation callback signature |
