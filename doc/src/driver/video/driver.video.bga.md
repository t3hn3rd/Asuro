# driver.video.bga

Bochs Graphics Adapter (BGA/VBE dispi) driver.

## Overview

This unit implements a driver for the Bochs Graphics Adapter, a virtual GPU present in QEMU and Bochs emulators. It communicates via two I/O ports to set resolution, colour depth, and enable the linear framebuffer. The driver registers with the GPU framework at priority 10 (higher than VESA) and with `driver.video` under the identifier `'BGA'`. On detection of BGA hardware via PCI, it calls `driver.video.gpu.markAvailable`.

## Dependencies

- `driver.video`
- `driver.video.types`
- `driver.video.gpu`
- `driver.bus.pci`
- `driver.types`
- `syslog`

## Boot Registration

Registered with `boot.mgr` as `driver.video.bga`, depending on `driver.video`.

## Constants

### I/O Ports
- `BGA_INDEX_PORT`: `$01CE` — write the register index here
- `BGA_DATA_PORT`: `$01CF` — read or write the register value here

### Register Indices
`BGA_REG_ID` (`$00`), `BGA_REG_XRES` (`$01`), `BGA_REG_YRES` (`$02`), `BGA_REG_BPP` (`$03`), `BGA_REG_ENABLE` (`$04`), `BGA_REG_BANK` (`$05`), `BGA_REG_VIRT_WIDTH` (`$06`), `BGA_REG_VIRT_HEIGHT` (`$07`), `BGA_REG_X_OFFSET` (`$08`), `BGA_REG_Y_OFFSET` (`$09`).

### Enable Flags
- `BGA_DISABLED`: `$00`
- `BGA_ENABLED`: `$01`
- `BGA_LFB_ENABLED`: `$40` — enables the linear framebuffer mode

### BGA Version Range
`BGA_ID_MIN`: `$B0C0`, `BGA_ID_MAX`: `$B0C5`. Valid BGA versions are detected by reading register 0 and checking this range.

### PCI Identification
Vendor ID `$1234`, device ID `$1111`. Used to locate the BGA PCI device and read its BAR0 framebuffer address.

## Functions and Procedures

### init
```pascal
procedure init(Register: FRegisterDriver);
```
Registers this driver with `driver.video` under `'BGA'` and calls `driver.video.gpu.registerDriver` with priority 10. Then calls `load` to detect and initialise hardware.

### load
```pascal
function load(ptr: pointer): boolean;
```
Driver load callback (also called directly from `init`). Reads the BGA version register; if the version is within `BGA_ID_MIN`..`BGA_ID_MAX`, locates the PCI device (vendor `$1234`, device `$1111`) to obtain the framebuffer physical address, sets `BGAPresent := true`, stores the framebuffer address in `BGAFramebuffer`, and calls `driver.video.gpu.markAvailable('BGA')`.

### setMode
```pascal
function setMode(width, height, bpp: uint32; out info: TGPUModeInfo): boolean;
```
Disables the BGA display, writes the new XRES/YRES/BPP registers, re-enables with `BGA_ENABLED or BGA_LFB_ENABLED`, fills `info` with framebuffer address and geometry, and returns `true`.

## Notes

- BGA does not require BIOS calls; all configuration is performed via the two I/O ports, making it suitable for use before the v86 monitor is initialised.
- The linear framebuffer address is read from PCI BAR0 of the device at vendor `$1234` / device `$1111`.
