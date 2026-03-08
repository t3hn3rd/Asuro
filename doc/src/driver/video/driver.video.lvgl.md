# driver.video.lvgl

Pascal bindings for the LVGL 9.x embedded GUI library.

## Overview

This unit provides Free Pascal type declarations and `external` function imports for the LVGL 9.x C library. It exposes opaque pointer types for all major LVGL objects, stack-allocatable record types with known sizes for styles and animations, colour types, and the full LVGL widget and drawing API surface used by `driver.video.desktop` and `driver.video.windows`.

## Dependencies

- (LVGL shared library / linked object — C ABI)

## Types

### Opaque Pointer Types
All major LVGL object types are declared as opaque pointers to avoid exposing the internal C struct layouts:

`Plv_display`, `Plv_indev`, `Plv_obj`, `Plv_group`, `Plv_theme`, `Plv_font_t`, `Plv_style_t` (pointer), `Plv_anim_t` (pointer), `Plv_event_t`, `Plv_timer_t`.

### Stack-Allocatable Types
These types have fixed known sizes matching their C struct counterparts and can be allocated on the Pascal stack or in records:

| Type | Size | Description |
|---|---|---|
| `lv_style_t` | 16 bytes | Style descriptor |
| `lv_anim_t` | 128 bytes | Animation descriptor |
| `lv_style_transition_dsc_t` | 24 bytes | Style transition descriptor |

### Colour Types

```pascal
lv_color32_t = packed record
  blue  : uint8;
  green : uint8;
  red   : uint8;
  alpha : uint8;
end;
lv_color_t = lv_color32_t;
```
32-bit BGRA colour value matching LVGL's native colour format.

### lv_area_t
```pascal
lv_area_t = record
  x1, y1, x2, y2 : sint32;
end;
```
Axis-aligned bounding rectangle used throughout the LVGL drawing API.

### Enumerations
LVGL state flags (`LV_STATE_*`), part selectors (`LV_PART_*`), alignment constants (`LV_ALIGN_*`), layout types (`LV_LAYOUT_*`), flex flow and alignment values, text alignment, border sides, and event codes (`LV_EVENT_*`) are declared as typed constants or enumerations matching the C header values.

## Notes

- All LVGL functions are imported via `external` declarations using the C calling convention. The LVGL library must be linked into the kernel binary.
- Only the subset of the LVGL API actually used by the desktop and window manager is bound; the complete LVGL API is not fully mapped.
- `lv_color_t` is always 32-bit in this build; LVGL is compiled with `LV_COLOR_DEPTH=32`.
