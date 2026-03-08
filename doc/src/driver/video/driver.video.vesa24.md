# driver.video.vesa24

VESA 24bpp draw routines (stub).

## Overview

This unit is a stub for 24bpp (true colour, packed RGB) VESA framebuffer drawing operations. The `DrawPixel` procedure and `init` routine are present but not yet implemented. Only tracer calls are emitted on `init`.

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
Entry point called by the VESA driver when the active mode is 24bpp. Currently a no-op aside from tracer push/pop calls. Does not populate any function pointers in `DrawRoutines`.

## Notes

- 24bpp colour depth is not currently supported. Attempting to run at 24bpp will result in no rendering output.
