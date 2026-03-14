# driver.storage.boot

Boot drive identification bridge.

## Overview

This unit reads the BIOS boot device byte from the Multiboot information structure and passes it to the storage manager so it can identify the boot drive during device registration.

## Boot Registration

Registered with `boot.mgr` as `driver.storage.boot`, depending on `driver.storage.mgr`. Runs during the `storage` phase after the storage manager has initialised.

## Dependencies

- `boot.mgr`
- `driver.storage.mgr`
- `arch.x86.multiboot`

## Procedures

### init

```pascal
procedure init;
```

Extracts the top byte of `multibootinfo^.boot_device` (the BIOS drive number) and calls `driver.storage.mgr.set_boot_drive_byte` to record it. This allows the storage manager to match the boot device when AHCI or other controllers register their devices later.
