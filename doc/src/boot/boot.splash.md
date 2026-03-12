# boot.splash

Boot splash screen displaying the Asuro logo, a progress bar, and a status label during kernel initialization.

## Overview

`boot.splash` renders a full-screen LVGL splash screen that is visible while `kmain` works through the boot sequence. Because the graphics render daemon (`svc.gfxd`) has not yet started at this stage, `boot.splash` drives the LVGL timer pipeline and flushes the framebuffer manually on every update.

The screen uses a dark background (`#1A1A2E`) with a vertically-centred flex column containing three children: an LVGL image widget displaying the Asuro logo, a progress bar, and a status text label.

The logo is decoded at runtime from a TGA file that is embedded in the kernel binary via a NASM `incbin` stub. The decoded ARGB8888 pixel buffer is wrapped in a heap-allocated `TLVImageDsc` that conforms to the LVGL `lv_image_dsc_t` layout so it can be passed directly to `lv_image_set_src`.

`teardown` restores the previously-active LVGL screen, deletes all splash widgets, and frees the decoded texture and image descriptor.

## Dependencies

- `driver.video.lvgl`
- `driver.video`
- `core.fmt.targa`
- `core.gfx.texture`
- `memory.heap`

## Boot Registration

- `boot.splash` depending on `core.panic` — initialises the splash screen.
- `boot.splash.teardown` at the `final` barrier — tears down the splash screen after boot completes.

## Constants

### LV_IMAGE_HEADER_MAGIC
`$19` — Magic byte placed in the first byte of the LVGL `lv_image_header_t`.

### LV_CF_ARGB8888
`$10` — LVGL color format constant for 32-bit ARGB8888 pixel data.

### BAR_WIDTH / BAR_HEIGHT
`300` / `16` — Progress bar dimensions in pixels.

## Types

### TLVImageHeader

```pascal
TLVImageHeader = packed record
    magic_cf_flags : uint32;  { magic:8 | cf:8 | flags:16 }
    w_h            : uint32;  { w:16 | h:16 }
    stride_res     : uint32;  { stride:16 | reserved:16 }
end;
```

Mirrors `lv_image_header_t` with manual bitfield packing. `magic_cf_flags` encodes `LV_IMAGE_HEADER_MAGIC` in bits 0–7 and `LV_CF_ARGB8888` in bits 8–15. `stride` is set to `width * 4` bytes per pixel.

### TLVImageDsc / PLVImageDsc

```pascal
TLVImageDsc = packed record
    header    : TLVImageHeader;
    data_size : uint32;
    data      : pointer;
    reserved  : pointer;
end;
```

Mirrors the 24-byte `lv_image_dsc_t` on 32-bit. `data` points to the decoded ARGB pixel buffer; `data_size` is `width * height * 4`.

## Functions and Procedures

### init

```pascal
procedure init;
```

Saves the currently active LVGL screen, decodes the embedded TGA logo, creates the splash screen with a flex-column layout, and renders the first frame. The image is scaled to 50% (`lv_image_set_scale(logoImage, 128)`).

### update

```pascal
procedure update(percent: uint32; status: pchar);
```

Sets the progress bar value (clamped to 0..100), updates the status label text, redraws the frame, and calls `busywait_500ms` to hold the display visible for approximately 500 ms. Called by `kmain` at each boot milestone.

### teardown

```pascal
procedure teardown;
```

Restores the previous LVGL screen, deletes the splash screen object and all its children, and frees the heap-allocated image descriptor and decoded texture.

## Notes

`busywait_500ms` reads the PIT channel-0 counter in a tight loop without using interrupts, making it safe to call before `STI`. It counts approximately 4000 PIT rollovers (~500 ms at a ~8 kHz tick rate). This is a debug-only mechanism intended to make each boot step visible on screen.

The `redraw` helper passes a 100 ms tick increment to `lv_tick_inc` so LVGL always considers the display stale and renders pending invalidations immediately, without relying on the scheduler-driven tick source.

The embedded TGA data is referenced via linker-provided symbols `_splash_tga_start` and `_splash_tga_size` inserted by the NASM `incbin` stub.
