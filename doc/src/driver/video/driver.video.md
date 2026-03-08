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
- `syslog`

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

## Notes

- All drawing operations target the back buffer (`DefaultBuffer`) when double buffering is active. `Flush` transfers the result to the front (visible) buffer.
- `reinit` is called by the GPU framework on every successful mode change, including the initial mode set during boot.
