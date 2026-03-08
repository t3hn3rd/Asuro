# driver.video.windows

LVGL-based window manager.

## Overview

This unit implements a simple window manager on top of LVGL. Each window consists of a set of LVGL objects (frame, title bar, title label, close and collapse buttons, content area, and resize grip) managed as a `TWinRecord`. Up to `MAX_WINDOWS` windows can exist simultaneously. The manager handles creation, destruction, focus, collapse/expand, and drag/resize interactions.

## Dependencies

- `driver.video.lvgl`
- `driver.hid.mouse`
- `syslog`

## Constants

| Constant | Value | Description |
|---|---|---|
| `MAX_WINDOWS` | `16` | Maximum simultaneous open windows |
| `WIN_TITLEBAR_H` | `32` | Title bar height in pixels |
| `WIN_MIN_W` | `160` | Minimum window width in pixels |
| `WIN_MIN_H` | `80` | Minimum window height in pixels |
| `WIN_RESIZE_GRIP` | `16` | Size of the resize grip area in the bottom-right corner |
| `WIN_BORDER_RAD` | `10` | Window frame corner radius in pixels |

## Types

### TWinState
```pascal
TWinState = (wsNone, wsOpen, wsCollapsed);
```
Current state of a window slot. `wsNone` means the slot is unused.

### TWinRecord
Per-window state:

| Field | Type | Description |
|---|---|---|
| `frame` | `Plv_obj` | Outer window container |
| `titlebar` | `Plv_obj` | Title bar panel |
| `title` | `Plv_obj` | Title label |
| `close_btn` | `Plv_obj` | Close button |
| `collapse_btn` | `Plv_obj` | Collapse/expand button |
| `content` | `Plv_obj` | Content area returned to callers |
| `resize_grip` | `Plv_obj` | Resize drag handle in bottom-right corner |
| `state` | `TWinState` | Current window state |
| `drag_x`, `drag_y` | `sint32` | Mouse offset from window origin at drag start |
| `resize_w`, `resize_h` | `sint32` | Window size at resize start |
| `owner_pid` | `uint32` | PID of the owning process (reserved for future use) |

## Functions and Procedures

### createWindow
```pascal
function createWindow(title: string; x, y, w, h: sint32): uint32;
```
Allocates the next free window slot, creates all LVGL objects with the specified title, position, and dimensions, and returns the window handle (slot index). Returns `MAX_WINDOWS` if no slot is available.

### getWindowContent
```pascal
function getWindowContent(handle: uint32): Plv_obj;
```
Returns the LVGL content container for the window identified by `handle`. Callers add their own widgets as children of this object.

### getWindowFrame
```pascal
function getWindowFrame(handle: uint32): Plv_obj;
```
Returns the outer frame object for the window. Used when the caller needs to position or style the window container directly.

### destroyWindow
```pascal
procedure destroyWindow(handle: uint32);
```
Deletes all LVGL objects for the window and marks the slot as `wsNone`.

### focusWindow
```pascal
procedure focusWindow(handle: uint32);
```
Brings the window to the front of the LVGL z-order and sets keyboard focus.

### isWindowOpen
```pascal
function isWindowOpen(handle: uint32): boolean;
```
Returns `true` if the given handle refers to a window in `wsOpen` or `wsCollapsed` state.

### getWindowCount
```pascal
function getWindowCount: uint32;
```
Returns the number of currently open windows (slots with state `wsOpen` or `wsCollapsed`).

## Notes

- Drag behaviour is implemented via LVGL `LV_EVENT_PRESSING` callbacks on the title bar: the window position is updated each frame by the delta between the current mouse position and the drag anchor recorded at `LV_EVENT_PRESSED`.
- Resize behaviour uses the resize grip object's press/drag events in the same manner.
- Collapsed windows retain their frame and title bar but hide the content area, reducing height to `WIN_TITLEBAR_H`.
