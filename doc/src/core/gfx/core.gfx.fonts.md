# core.gfx.fonts

Standard bitmap font mask data for kernel text rendering.

## Overview

`core.gfx.fonts` provides a pre-baked bitmap font mask used by the kernel's software text renderer. The font data is stored as a large compile-time constant array of `uint16` values (`Std_Mask`) that encodes the pixel patterns for the full printable ASCII character set. Each `$FFFF` entry represents an opaque (set) pixel; each `$0000` represents a transparent (clear) pixel. The renderer in the video subsystem indexes into this array by character code and glyph row to determine which pixels to draw.

## Dependencies

None.

## Constants

### Std_Mask
```pascal
Std_Mask : Array[0..32768] of uint16;
```
A 32769-element array of `uint16` values encoding the pixel masks for the standard kernel font. Each character occupies a fixed-width, fixed-height glyph cell. The array is indexed by `(character_code * glyph_height * glyph_width) + (row * glyph_width) + column`, with `$FFFF` indicating a set pixel and `$0000` indicating a clear pixel.

## Notes

The font data is a compile-time constant and requires no runtime initialisation. It occupies approximately 64 KiB in the kernel image (32769 × 2 bytes).

This unit contains only font data; no rendering functions are defined here. The actual rendering logic that consumes `Std_Mask` is located in the video driver subsystem.
