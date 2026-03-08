# app.diskutil

Graphical disk utility application for inspecting and managing storage devices.

## Overview

`app.diskutil` provides a windowed GUI application (launched from the desktop) that presents a two-pane interface for working with storage. The left sidebar lists all registered physical devices and their volumes. Selecting an item populates the right-hand detail panel with device or volume information. From the detail panel the user can add or remove partitions and format volumes with any registered filesystem.

The application runs as a registered desktop program and creates an associated process entry so it appears in the process list.

## Dependencies

- `driver.video.desktop`, `driver.video.lvgl`, `driver.video`, `driver.video.windows`
- `driver.storage.fs.mgr`, `driver.storage.mgr`, `driver.storage.types`
- `driver.storage.vol.mbr`, `driver.storage.vol.mgr`
- `memory.heap`, `core.strings`, `io.syslog`, `debug.tracer`
- `proc.mgr`, `proc.types`

## Constants

### WIN_W / WIN_H
`740` / `480` — Window dimensions in pixels.

### SIDEBAR_W
`210` — Width of the device/volume sidebar in pixels.

### SEL_NONE / SEL_DEVICE / SEL_VOLUME
`0` / `1` / `2` — Selection mode values tracking whether nothing, a device, or a volume is currently selected.

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the application with `driver.video.desktop` under the name `DiskUtil`. The window is created when the user launches it from the desktop environment.

### launch (internal)

Creates the LVGL window, populates the sidebar with all storage devices and their volumes, and spawns a process so the application appears in `PS`.

### refreshSidebar (internal)

Rebuilds the sidebar button list to reflect the current state of registered devices and volumes.

### showDeviceDetail / showVolumeDetail (internal)

Populates the detail panel with properties for the selected device or volume respectively, including action buttons for partition management and formatting.

## Notes

Only one instance of the disk utility window may be open at a time. Destructive operations (partition deletion, formatting) present a confirmation message box before proceeding. The format dropdown is populated from all filesystems registered with `driver.storage.fs.mgr` at the time the detail panel is shown.
