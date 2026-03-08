# core.gfx.texture

Texture allocation and the core pixel-buffer type.

## Overview

`core.gfx.texture` defines the `TTexture` record that represents a 2D pixel buffer, and provides the `newTexture` factory function to allocate one from the kernel heap. Textures are used by the TGA image parser (`core.fmt.targa`), the kernel panic screen, and any other subsystem that needs to hold a rectangular BGRA pixel array.

## Dependencies

- `memory.heap` — `kalloc`
- `core.gfx.color` — `TRGB32`, `PRGB32`

## Types

### TTexture / PTexture
```pascal
TTexture = packed record
    Width  : uint32;
    Height : uint32;
    Size   : uint32;
    Pixels : PRGB32;
end;
```
A 2D pixel buffer.

- `Width` — image width in pixels.
- `Height` — image height in pixels.
- `Size` — total pixel count (`Width * Height`).
- `Pixels` — pointer to a contiguous heap-allocated array of `TRGB32` pixels in row-major order (row 0 first, left to right within each row).

## Functions and Procedures

### newTexture
```pascal
function newTexture(width, height: uint32): PTexture;
```
Allocates a new `TTexture` and its associated `Pixels` buffer of `width * height * sizeof(TRGB32)` bytes. Both the structure and the pixel buffer are allocated from the kernel heap. Returns a pointer to the initialised `TTexture`. The pixel buffer is not zeroed; callers should write all pixels before reading.

## Notes

There is no `freeTexture` function. Callers that need to release a texture must call `kfree` on `Texture^.Pixels` and then `kfree` on the `TTexture` pointer itself.

The pixel buffer layout is BGRA, matching the `TRGB32` type defined in `core.gfx.color`. Pixel at coordinates `(x, y)` is at `Pixels[y * Width + x]`.
