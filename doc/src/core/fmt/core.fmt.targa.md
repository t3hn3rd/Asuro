# core.fmt.targa

TGA (Truevision TARGA) image file parser.

## Overview

`core.fmt.targa` decodes uncompressed type-2 true-colour images with 24-bit or 32-bit pixels into BGRA textures. It handles both row and column origins and rejects truncated pixel data.

The primary consumer of this unit is `core.panic`, which uses it to decode the embedded teapot image displayed on the kernel panic screen.

## Dependencies

- `memory.heap` — `kalloc` (via `core.gfx.texture`)
- `core.gfx.texture` — `newTexture`, `PTexture`

## Types

### TTARGAColor / PTARGAColor
```pascal
TTARGAColor = packed record
    b, g, r, a: uint8;
end;
```
A single 32-bit pixel in the TGA source format (BGRA byte order).

### TTARGAHeader / PTARGAHeader
```pascal
TTARGAHeader = packed record
    IDLength        : uint8;
    ColorMapType    : uint8;
    ImageType       : uint8;
    ColorMapOrigin  : uint16;
    ColorMapLength  : uint16;
    ColorMapDepth   : uint8;
    XOrigin         : uint16;
    YOrigin         : uint16;
    Width           : uint16;
    Height          : uint16;
    PixelDepth      : uint8;
    ImageDescriptor : uint8;
end;
```
The 18-byte TGA file header. `ImageType` must be `2` (uncompressed true-colour). `PixelDepth` must be `24` or `32`. Pixel data begins immediately after the header plus any optional ID field (`IDLength` bytes).

## Functions and Procedures

`ParseScaled` takes an offset reader, a source length, and target dimensions.
It crops to the target aspect ratio and decodes using one source row at a
time. The desktop uses it to load wallpapers through the VFS.

### Parse
```pascal
function Parse(buffer : puint8; len : uint32) : PTexture;
```
Parses a TGA image from `len` bytes at `buffer`. Returns a heap-allocated `TTexture` containing the decoded pixel data in BGRA order, or `nil` if:
- `len` is smaller than the header size,
- `ImageType` is not `2`, or
- `PixelDepth` is not `32`.

Vertical orientation is determined by bit 5 of `ImageDescriptor`: `1` = top-to-bottom (stored as-is); `0` = bottom-to-top (rows are flipped during copy).

## Notes

Only 32-bit uncompressed TGA files are supported. Run-length encoded (type 10), colour-mapped (type 1), or other image types are rejected.

The output texture pixel layout mirrors the TGA source: BGRA byte order matching `TRGB32` (B at the lowest address, then G, R, A). Callers consuming the texture for LVGL display must ensure the LVGL colour format matches this layout, or convert appropriately.
