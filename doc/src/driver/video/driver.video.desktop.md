# driver.video.desktop

LVGL-based graphical desktop shell.

## Overview

This unit implements the Asuro graphical desktop environment using the LVGL 9.x widget library. It provides a gradient background, a floating macOS-style dock, a search box for launching registered programs, a clock label, and a software mouse cursor. A system information panel can be opened from the dock. The desktop responds to GPU mode changes by invoking `relayout` to reposition elements for the new resolution.

## Dependencies

- `driver.video.lvgl`
- `driver.video.gpu`
- `driver.hid.mouse`
- `driver.timer.rtc`
- `syslog`

## Functions and Procedures

### init
```pascal
procedure init;
```
Creates all LVGL objects: gradient background, dock container with application icons, search textarea, clock label, and mouse cursor object. Registers mouse hooks for dock interaction and search box activation. Registers `desktopModeChanged` as a GPU mode-change callback.

### update
```pascal
procedure update;
```
Called each kernel frame. Updates the clock label text from the RTC, advances LVGL's animation tick, and calls `lv_timer_handler`. Should be called at approximately 30–60 Hz.

### relayout
```pascal
procedure relayout;
```
Repositions all desktop elements to fit the current framebuffer resolution. Called automatically when the GPU mode changes via `desktopModeChanged`.

### registerProgram
```pascal
procedure registerProgram(name: string; launcher: procedure);
```
Adds an application to the program list. The `launcher` callback is invoked when the user activates the program from the search results or dock.

### openSysInfo (internal)
Creates a windowed system information panel displaying: CPU identification string, total and used memory, display resolution, active GPU driver name, OS version string, and CPU feature badges (SSE, SSE2, AVX, etc.).

### desktopModeChanged (internal callback)
Registered with the GPU framework. Calls `relayout` when the display mode changes.

## Notes

- Search results are filtered using case-insensitive substring matching (`ciContains`) and display up to 6 matches with a slide-in animation.
- The dock uses LVGL's flex layout with a fixed height; icon buttons are added programmatically for each registered program.
- The mouse cursor is an LVGL object that is repositioned each frame by reading `driver.hid.mouse.MouseX`/`MouseY`.
