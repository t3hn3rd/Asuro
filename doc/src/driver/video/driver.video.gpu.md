# driver.video.gpu

GPU driver registry and mode-change framework.

## Overview

This unit provides the GPU abstraction layer. Multiple GPU drivers (e.g. BGA, VESA/VBE) register themselves with a priority value; when a mode change is requested, drivers are tried in priority order until one succeeds. On a successful mode change, all registered mode-change callbacks are fired so that dependent subsystems (video front-end, desktop) can reconfigure themselves.

## Dependencies

- `driver.video.types`
- `syslog`

## Boot Registration

Registered with `boot.mgr` as `driver.video.gpu`, depending on `driver.mgr`.

## Constants

- `GPU_MAX_DRIVERS`: `8` — maximum number of simultaneously registered GPU drivers
- `GPU_MAX_CALLBACKS`: `8` — maximum number of mode-change callback slots

## Types

### TGPUModeInfo
Information block filled by a GPU driver's `SetMode` function on success:

| Field | Type | Description |
|---|---|---|
| `width` | `uint32` | Horizontal resolution in pixels |
| `height` | `uint32` | Vertical resolution in pixels |
| `bpp` | `uint8` | Bits per pixel |
| `framebuffer` | `pointer` | Physical address of the linear framebuffer |
| `pitch` | `uint32` | Bytes per scanline |

### TGPUDriver
Registration record for a single GPU driver:

| Field | Type | Description |
|---|---|---|
| `name` | `string` | Human-readable driver name |
| `priority` | `uint32` | Lower value = higher priority |
| `SetMode` | `function(w, h, bpp: uint32; out info: TGPUModeInfo): boolean` | Mode-set callback |
| `Available` | `boolean` | Whether this driver has been marked available |

## Functions and Procedures

### registerDriver
```pascal
procedure registerDriver(name: string; priority: uint32; SetMode: TGPUSetModeFunc);
```
Inserts a GPU driver into the driver list in priority order (ascending). Up to `GPU_MAX_DRIVERS` drivers may be registered.

### markAvailable
```pascal
procedure markAvailable(name: string);
```
Marks the named driver as available for mode-set attempts. Drivers not marked available are skipped by `setMode`.

### setMode
```pascal
function setMode(width, height, bpp: uint32): boolean;
```
Iterates registered drivers in priority order, skipping unavailable ones. Calls each driver's `SetMode` function with the requested parameters. On the first success, stores the driver name and calls `fireModeChangeCallbacks` with the returned `TGPUModeInfo`. Returns `true` if any driver succeeded.

### registerModeChangeCallback
```pascal
procedure registerModeChangeCallback(callback: TGPUModeChangeCallback);
```
Registers a callback to be invoked after every successful mode change. Up to `GPU_MAX_CALLBACKS` callbacks are supported.

### fireModeChangeCallbacks (internal)
```pascal
procedure fireModeChangeCallbacks(info: TGPUModeInfo);
```
Iterates and calls all registered mode-change callbacks with the new `TGPUModeInfo`.

### activeDriverName
```pascal
function activeDriverName: string;
```
Returns the name of the GPU driver that performed the most recent successful mode change, or an empty string if no mode has been set.

## Notes

- BGA is registered at priority 10 and VESA at priority 50, so BGA is always preferred when the hardware is present and `markAvailable` has been called.
- `setMode` does not cache the last requested resolution; callers that need to restore a mode after a driver switch must track the parameters themselves.
