# driver.video

Video subsystem front-end and draw routine dispatcher.

## Overview

This unit is the central video interface for the Asuro kernel. It holds a single `TVideoInterface` instance containing front and back buffer descriptors and a `TDrawRoutines` record of function pointers. Higher-level code calls drawing functions here, which dispatch to the BPP-specific implementation selected during `reinit`. It also manages a hashmap of named video drivers and registers a GPU mode-change callback so that the framebuffer is reconfigured automatically when the GPU changes resolution or BPP.

## Dependencies

- `driver.video.types`
- `driver.video.doublebuffer`
- `driver.video.gpu`
- `driver.video.vesa32` (and other BPP variants)
- `core.hashmap`
- `core.gfx.fonts` — 8×16 bitmap font data for text drawing
- `syslog`

## Boot Registration

- `driver.video` depending on `driver.video.gpu` — core video driver initialisation.
- `driver.video_late` depending on glob `driver.video.*` (waits for all matching entries) — late video initialisation after all video sub-drivers have registered.

## Functions and Procedures

### init
```pascal
procedure init;
```
Initialises the `VideoInterface` record with stub function pointers, creates the `DriverMap` hashmap, and registers `reinit` as a GPU mode-change callback.

### register
```pascal
procedure register(DriverIdentifier: string; EnableCallback: FEnableDriver);
```
Adds a named video driver to the `DriverMap`. The callback is invoked with a pointer to `VideoInterface` when the driver is enabled.

### enable
```pascal
procedure enable(DriverIdentifier: string);
```
Looks up `DriverIdentifier` in `DriverMap` and calls the stored `EnableCallback` with `@VideoInterface`.

### reinit
```pascal
procedure reinit(fb_addr: pointer; width, height, pitch, bpp: uint32);
```
Reconfigures the video interface after a GPU mode change:
1. Frees the existing back buffer if one was allocated.
2. Sets `FrontBuffer` fields from the provided framebuffer parameters.
3. Selects the BPP-appropriate draw routine set (currently only 32bpp is fully implemented).
4. Re-enables the double buffer.

### DrawPixel
```pascal
procedure DrawPixel(X, Y: uint32; Pixel: TRGB32);
```
Dispatches to `VideoInterface.DrawRoutines.DrawPixel`.

### DrawLine / DrawRect / FillRect
Similar dispatch wrappers for the other drawing operations.

### Flush
```pascal
procedure Flush;
```
Dispatches to `VideoInterface.DrawRoutines.Flush`, copying the back buffer to the front buffer.

### frontBufferWidth / frontBufferHeight / frontBufferBPP / frontBufferPitch
Accessor functions returning the corresponding field from `VideoInterface.FrontBuffer`.

### backBuffer
```pascal
function backBuffer: PVideoBuffer;
```
Returns a pointer to `VideoInterface.BackBuffer`.

## Text Drawing

These functions render text directly to the framebuffer using the 8×16 bitmap font from `core.gfx.fonts`. They are useful for panic screens or other contexts where LVGL is unavailable. Each function returns the X coordinate immediately after the last drawn pixel, allowing calls to be chained for inline formatting.

### DrawChar
```pascal
function DrawChar(X, Y : uint32; C : char; Color : TRGB32) : uint32;
```
Draws a single 8×16 bitmap glyph at `(X, Y)` in the given colour. Returns `X + 8`.

### DrawString
```pascal
function DrawString(X, Y : uint32; Str : pchar; Color : TRGB32) : uint32;
```
Draws a null-terminated string starting at `(X, Y)`. Each character advances X by 8 pixels. Returns the X coordinate after the last character.

### DrawHex
```pascal
function DrawHex(X, Y : uint32; Value : uint32; Color : TRGB32) : uint32;
```
Draws a `uint32` as a `0xHHHHHHHH` hex string at `(X, Y)`. Returns the X coordinate after the string.

### DrawInt
```pascal
function DrawInt(X, Y : uint32; Value : uint32; Color : TRGB32) : uint32;
```
Draws an unsigned integer in decimal at `(X, Y)`. Returns the X coordinate after the last digit.

## Notes

- All drawing operations target the back buffer (`DefaultBuffer`) when double buffering is active. `Flush` transfers the result to the front (visible) buffer.
- `reinit` is called by the GPU framework on every successful mode change, including the initial mode set during boot.
