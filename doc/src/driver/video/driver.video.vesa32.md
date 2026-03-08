# driver.video.vesa32

VESA 32bpp draw routines.

## Overview

This unit provides the 32bpp (true colour with padding byte) VESA framebuffer drawing implementation. It is the only fully implemented BPP variant in the VESA driver set. The `init` procedure registers `DrawPixel` in the `DrawRoutines` record; additional drawing operations (lines, rectangles) are provided by the generic layer or are stubs.

## Dependencies

- `driver.video.types`
- `driver.video.vesa`
- `debug.tracer`
- `core.gfx.color`

## Functions and Procedures

### init
```pascal
procedure init(DrawRoutines: PDrawRoutines);
```
Sets `DrawRoutines^.DrawPixel := @DrawPixel`. Called by the VESA driver when the active mode is 32bpp.

### DrawPixel (internal)
```pascal
procedure DrawPixel(Buffer: PVideoBuffer; X, Y: uint32; Pixel: TRGB32);
```
Writes a single 32-bit pixel value to the framebuffer at coordinate (X, Y) using the formula:

```
Buffer^.Location[Y * Buffer^.Width + X] := uint32(Pixel)
```

## Notes

- Pixel format is 32-bit BGRA (or XRGB depending on the BIOS mode), matching the `lv_color32_t` layout used by LVGL.
- No bounds checking is performed; callers are responsible for ensuring X < Width and Y < Height.
