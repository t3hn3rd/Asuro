# driver.video.vesa

VESA VBE mode-setting driver.

## Overview

This unit implements VESA BIOS Extensions (VBE) mode setting via v86 real-mode BIOS calls. It registers with the GPU framework and `driver.video`, calls into the BIOS to enumerate and activate a video mode matching the requested resolution and BPP, and maps the VBE linear framebuffer into kernel virtual memory. This is the fallback GPU driver and is used on hardware where no native GPU driver (e.g. BGA) is available.

## Dependencies

- `driver.video`
- `driver.video.types`
- `driver.video.gpu`
- `core.paging`
- `core.v86`
- `syslog`

## Constants

### VBE Buffer Addresses
- `VBE_INFO_ADDR`: `$1000` — physical address in low memory for the VBE information block (returned by INT 10h AX=4F00h)
- `VBE_MODE_INFO_ADDR`: `$1200` — physical address for the VBE mode information block (returned by INT 10h AX=4F01h)

## Functions and Procedures

### init
```pascal
procedure init(Register: FRegisterDriver);
```
Registers this driver with `driver.video` under the identifier `'VESA'`. Also registers `vbeSetModeGPU` with the GPU framework at priority 50.

### setMode
```pascal
function setMode(width, height, bpp: uint32): boolean;
```
Invokes the v86 BIOS to iterate available VBE modes and locate one matching the requested dimensions and colour depth. If found, calls INT 10h AX=4F02h to activate it, then calls `allocateVESAFrameBuffer` to map the framebuffer pages. Returns `true` on success.

### vbeSetModeGPU
```pascal
function vbeSetModeGPU(width, height, bpp: uint32; out info: TGPUModeInfo): boolean;
```
Wrapper called by the GPU framework when attempting a mode change. Calls `setMode` and fills `info` with the framebuffer address, dimensions, BPP, and pitch from the VBE mode information block. Returns `true` on success.

### allocateVESAFrameBuffer
```pascal
procedure allocateVESAFrameBuffer(phys_addr: uint32; size: uint32);
```
Maps `size` bytes of the VBE linear framebuffer starting at physical address `phys_addr` into the kernel address space using `kpalloc`.

## Notes

- VBE mode setting requires the v86 monitor to be active; this unit is only functional in an x86 environment with a BIOS present.
- The VBE information block and mode information block are written to fixed low-memory addresses (`$1000` and `$1200`) by the BIOS; these areas must not be used for other purposes during mode enumeration.
- VESA is registered at GPU priority 50, lower priority than BGA (priority 10), so BGA is preferred when available.
