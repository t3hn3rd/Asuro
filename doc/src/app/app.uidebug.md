# app.uidebug

Toggleable real-time diagnostic overlay for the LVGL desktop.

## Overview

`app.uidebug` provides a semi-transparent diagnostic panel that floats over all other UI content. When visible it displays live system metrics updated every frame: FPS, open window count, screen widget count, mouse position, LVGL tick counter, total memory, and screen resolution. A rolling FPS history chart with auto-scaling Y axis is rendered below the text rows.

The overlay is toggled by calling `toggle` (typically wired to F12 in the keyboard handler). It does not register a terminal command; it is controlled programmatically.

## Dependencies

- `driver.video.lvgl`
- `driver.video.windows`
- `driver.hid.mouse`
- `driver.video`
- `arch.x86.multiboot`
- `debug.tracer`

## Constants

### PANEL_W / PANEL_H
`220` / `280` — Default panel dimensions (auto-sized to content in practice).

### FPS_INTERVAL
`1000` — Milliseconds between FPS recalculations.

### GRAPH_SAMPLES
`60` — Number of FPS history data points in the ring buffer.

### GRAPH_MAX_FPS
`120` — Maximum Y-axis value for the FPS graph (used as a fallback; the graph auto-scales to actual min/max).

## Functions and Procedures

### update

```pascal
procedure update;
```

Must be called once per frame from the main render loop (before `lvgl_handler`). If the overlay is visible, refreshes all label text and updates the FPS graph. Uses a static 64-byte scratch buffer for label strings to avoid heap allocation per frame.

### toggle

```pascal
procedure toggle;
```

Shows the overlay if it is currently hidden, or destroys it if it is visible. Resets FPS tracking state on show.

### isVisible

```pascal
function isVisible: boolean;
```

Returns `true` if the overlay is currently displayed.

## Notes

The overlay is always moved to the foreground on each `update` call via `lv_obj_move_foreground`. Label updates use a module-level static character buffer (`buf`) to avoid per-frame heap allocations. The widget count displayed is only the direct child count of the active screen, not a full recursive widget tree count.
