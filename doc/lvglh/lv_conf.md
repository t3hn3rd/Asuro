# lv_conf.h

LVGL v9.2.2 configuration header tailored for the Asuro bare-metal kernel environment.

## Overview

This file configures the LVGL graphics library for use inside the Asuro kernel, where no standard C library, operating system, or GPU hardware is available. It selects a 32-bit XRGB8888 color depth to match the VESA framebuffer, routes all stdlib functionality through LVGL's built-in implementations, enables only the software renderer, and disables every hardware backend, filesystem driver, and image decoder. The result is a minimal but functional GUI stack that runs entirely in kernel space.

## Configuration Options / Defines

### Color Settings

#### LV_COLOR_DEPTH
Value: `32`. Matches the VESA XRGB8888 framebuffer used by Asuro.

### Standard Library Wrappers

#### LV_USE_STDLIB_MALLOC / LV_USE_STDLIB_STRING / LV_USE_STDLIB_SPRINTF
Value: `LV_STDLIB_BUILTIN`. All three are set to use LVGL's own built-in implementations since no libc is available in the bare-metal environment.

### Memory Pool

#### LV_MEM_SIZE
Value: `256 * 1024U` (256 KB). Size of LVGL's internal memory pool for widget allocations and draw buffers.

#### LV_MEM_POOL_EXPAND_SIZE
Value: `0`. Pool expansion is disabled; the 256 KB allocation is fixed.

#### LV_MEM_ADR
Value: `0`. LVGL allocates the pool itself rather than using a fixed address.

### HAL Settings

#### LV_DEF_REFR_PERIOD
Value: `33` (milliseconds). Targets approximately 30 frames per second.

#### LV_DPI_DEF
Value: `96`. Standard screen DPI assumption.

### Operating System

#### LV_USE_OS
Value: `LV_OS_NONE`. No OS abstraction layer; LVGL runs in a bare-metal cooperative model.

### Rendering Configuration

#### LV_USE_DRAW_SW
Value: `1`. The software renderer is the sole rendering backend.

Only the color formats actually used are enabled within the software renderer:

| Define | Value | Description |
|--------|-------|-------------|
| `LV_DRAW_SW_SUPPORT_XRGB8888` | 1 | Primary framebuffer format |
| `LV_DRAW_SW_SUPPORT_ARGB8888` | 1 | Alpha-blended surfaces |
| `LV_DRAW_SW_SUPPORT_RGB888` | 1 | 24-bit fallback |
| `LV_DRAW_SW_SUPPORT_RGB565` | 0 | Disabled |
| All other formats | 0 | Disabled |

#### LV_DRAW_SW_COMPLEX
Value: `1`. Enables complex draw operations (shadows, rounded corners). Shadow cache is disabled (`LV_DRAW_SW_SHADOW_CACHE_SIZE = 0`); circle cache is set to 4 entries.

#### LV_DRAW_LAYER_SIMPLE_BUF_SIZE
Value: `24 * 1024` (24 KB). Buffer for simple layer rendering.

#### GPU Backends
All GPU-accelerated backends are disabled: VGLite, PXP, Dave2D, SDL, VG-Lite.

### Logging

#### LV_USE_LOG
Value: `1`. Logging is enabled at `LV_LOG_LEVEL_WARN`. Printf-based logging, timestamps, and file/line info are all disabled to reduce overhead. All trace categories (memory, timer, indev, display refresh, events, object creation, layout, animation, cache) are disabled.

### Assertions

#### LV_USE_ASSERT_NULL / LV_USE_ASSERT_MALLOC
Value: `1`. Null-pointer and malloc-failure assertions are active.

#### LV_ASSERT_HANDLER
Value: `{}` (no-op). The assert handler intentionally does nothing to avoid hanging the kernel on a failed assertion.

### Fonts

#### LV_FONT_MONTSERRAT_14
Value: `1`. The only built-in Montserrat size enabled.

#### LV_FONT_DEFAULT
Value: `&lv_font_montserrat_14`. All other Montserrat sizes (8--48), compressed variants, and alternative font families (DejaVu, SimSun, UNSCII) are disabled.

### Text Settings

#### LV_TXT_ENC
Value: `LV_TXT_ENC_UTF8`. UTF-8 text encoding. BiDi and Arabic/Persian character support are disabled.

### Widgets

Enabled widgets: AnimImg, Arc, Bar, Button, ButtonMatrix, Checkbox, Dropdown, Image, Keyboard, Label, Line, List, MsgBox, Roller, Slider, Spinner, Switch, TextArea, Table, TabView, Win.

Disabled widgets: Calendar, Canvas, Chart, ImageButton, LED, Lottie, Menu, Scale, Span, SpinBox, TileView.

### Themes

#### LV_USE_THEME_DEFAULT
Value: `1`. Dark mode enabled (`LV_THEME_DEFAULT_DARK = 1`) with 80 ms transition time.

#### LV_USE_THEME_SIMPLE
Value: `1`.

#### LV_USE_THEME_MONO
Value: `0`.

### Layouts

Both Flex and Grid layout engines are enabled.

### Third-Party Libraries

All filesystem drivers are disabled (stdio, POSIX, Win32, FatFS, MemFS, LittleFS). All image decoders are disabled (PNG, BMP, JPEG, GIF, RLE). FreeType, TinyTTF, Rlottie, vector graphics, LZ4, and FFmpeg are all disabled.

### Device Drivers

All platform-specific device drivers are disabled (SDL, X11, Wayland, Linux FBDEV, Linux DRM, NuttX, various SPI display controllers, Windows, OpenGLES, QNX). Display and input are handled by Asuro's own HAL layer.

### Examples and Demos

All built-in examples and demo applications are disabled.

## Notes

- The configuration is designed for minimal footprint. Features are enabled only when required by the Asuro desktop shell.
- Since no libc is linked, all string, memory, and formatting operations fall through to LVGL's internal implementations.
- The assert handler is a deliberate no-op to prevent the kernel from halting on non-critical UI assertion failures.
- The 256 KB memory pool is fixed and cannot expand at runtime. UI complexity must stay within this budget.
