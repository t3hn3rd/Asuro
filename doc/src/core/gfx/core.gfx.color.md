# core.gfx.color

Colour type definitions and predefined colour constants for kernel graphics.

## Overview

`core.gfx.color` defines the packed record types used to represent pixels at different colour depths (32-bit, 24-bit, 16-bit, and 8-bit) and provides a small set of named colour constants for the 32-bit BGRA format. These types are used by the texture, video, and format units throughout the kernel graphics subsystem.

## Dependencies

None.

## Types

### TRGB32 / PRGB32
```pascal
TRGB32 = bitpacked record
    B : uint8;
    G : uint8;
    R : uint8;
    A : uint8;
end;
```
32-bit BGRA pixel. Bytes are stored in memory order B, G, R, A. This layout is common for framebuffers and matches the TGA pixel order used by `core.fmt.targa`.

### TRGB24 / PRGB23
```pascal
TRGB24 = bitpacked record
    B : uint8;
    G : uint8;
    R : uint8;
end;
```
24-bit BGR pixel with no alpha channel. Note: the pointer type is named `PRGB23` (a typo in the source; the underlying type is `TRGB24`).

### TRGB16 / PRGB16
```pascal
TRGB16 = bitpacked record
    B : UBit5;
    G : UBit6;
    R : UBit5;
end;
```
16-bit BGR565 pixel. Blue and red are 5 bits each; green is 6 bits. Used for 16-bit video modes.

### TRGB8 / PRGB8
```pascal
TRGB8 = bitpacked record
    B : UBit2;
    G : UBit4;
    R : UBit2;
end;
```
8-bit packed BGR pixel (2-4-2 bit layout). Used for 8-bit video modes.

## Constants

The following `TRGB32` colour constants are provided:

| Name    | B   | G   | R   | A   |
|---------|-----|-----|-----|-----|
| `black` | 0   | 0   | 0   | 0   |
| `white` | 255 | 255 | 255 | 0   |
| `red`   | 0   | 0   | 255 | 0   |
| `green` | 0   | 255 | 0   | 0   |
| `blue`  | 255 | 0   | 0   | 0   |

All constants have an alpha value of 0.

## Notes

Colour channel order in `TRGB32` is BGRA (blue at the lowest byte address), not RGBA. Code that consumes these values as raw 32-bit integers should account for the byte order of the target hardware or framebuffer format.
