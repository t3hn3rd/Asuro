# core.panic

Architecture-agnostic kernel panic (BSOD) engine.

## Overview

`core.panic` implements a graphical and serial kernel panic handler for the Asuro kernel. When a fatal condition is detected anywhere in the kernel, `panic` is called with a fault identifier, a human-readable description, and an optional CPU register snapshot. All diagnostic sections (Fault Info, CPU Registers, Process Info, System Info, Call Stack) are mirrored to the serial syslog for headless debugging. If LVGL has been initialised, a graphical Blue Screen of Death (BSOD) is displayed.

If the panic occurs inside the `gfxd` graphics-rendering process, LVGL state may be corrupt. In this case the unit falls back to rendering the panic screen directly to the VESA framebuffer using `driver.video.DrawString`, `driver.video.DrawHex`, and `driver.video.DrawInt`, bypassing LVGL entirely.

The BSOD screen and all its LVGL widgets are pre-allocated at `init` time so that no dynamic LVGL allocation is needed when a panic fires. At panic time only label text is updated via `lv_label_set_text`, the pre-built screen is loaded, and a single render pass is forced. Text formatting uses static heap buffers and avoids calling any string library routines that might themselves fault.

Architecture-specific code is responsible for registering a CPU halt routine with `registerHaltProc` before any panic can occur. If no halt procedure is registered, the default fallback loops forever.

If `init` has not been called before a panic (early boot panic), the unit gracefully falls back to syslog-only output.

## Dependencies

- `io.syslog` — serial fault output
- `debug.tracer` — call-stack capture and freeze
- `driver.video` — frame buffer flush and text drawing (DrawString, DrawHex, DrawInt) for VESA fallback
- `memory.heap` — buffer allocation
- `driver.video.lvgl` — LVGL widget creation and rendering
- `core.version` — version constants for the system info panel
- `proc.mgr` — current process information
- `proc.types` — process state enumeration
- `core.fmt.targa` — teapot TGA image decoding
- `core.gfx.texture` — pixel buffer type
- `core.strings` — string comparison for gfxd process detection
- `core.gfx.color` — TRGB32 colour type for direct pixel drawing

## Boot Registration

Registered with `boot.mgr` as `core.panic`, depending on glob `arch.*.panic` (waits for all matching entries).

## Constants

### MAX_REGISTER_ENTRIES
Maximum number of register name/value pairs an architecture can supply in a `TRegisterSnapshot`. Value: `32`.

### PANIC_TEXT_BUF_SIZE
Size in bytes of the pre-allocated text buffers used to format register, trace, process, and system information. Value: `2048`.

## Types

### TRegisterEntry
```pascal
TRegisterEntry = record
    Name  : pchar;
    Value : uint32;
end;
```
A single name/value pair representing one CPU register. `Name` must be a static string literal or a pointer that remains valid for the kernel lifetime.

### TRegisterSnapshot / PRegisterSnapshot
```pascal
TRegisterSnapshot = record
    Count   : uint32;
    Entries : array[0..MAX_REGISTER_ENTRIES-1] of TRegisterEntry;
end;
```
A snapshot of CPU register state at the time of a fault. `Count` specifies how many entries in `Entries` are valid.

### THaltProc
```pascal
THaltProc = procedure;
```
Procedure type for the architecture-specific CPU halt routine.

## Functions and Procedures

### init
```pascal
procedure init;
```
Creates the hidden BSOD LVGL screen and pre-allocates all widget objects and text buffers. Must be called once after LVGL has been initialised. Subsequent calls to `panic` will display the graphical BSOD only if `init` has been called first.

### panic
```pascal
procedure panic(fault : pchar; info : pchar; regs : PRegisterSnapshot);
```
Triggers a kernel panic. Freezes the call-stack tracer, dumps all diagnostic sections (Fault Info, CPU Registers, Process Info, System Info, Call Stack) to syslog, and displays the graphical panic screen. If the crash occurred in the `gfxd` process, LVGL is bypassed and the screen is rendered directly to the VESA framebuffer. Otherwise, if the LVGL BSOD screen is ready, it is used. Then calls the registered halt procedure. Re-entrant calls are detected by a guard flag; if `panic` is called while a panic is already in progress, the system halts immediately without further output.

Parameters:
- `fault` — short fault identifier string, e.g. `'arch.x86.fault.gpf'`.
- `info` — human-readable description of the fault.
- `regs` — pointer to a `TRegisterSnapshot`, or `nil` if register state is unavailable.

### registerHaltProc
```pascal
procedure registerHaltProc(proc : THaltProc);
```
Registers the architecture-specific halt procedure. Must be called before any panic can occur. If not called, a fallback infinite loop is used.

## Notes

The BSOD layout consists of a top banner (teapot TGA image beside title text) and a two-column content area. The left column contains Fault Details, CPU Registers, Process Info, and System Info cards. The right column contains the full-height Call Stack card.

The teapot image is loaded from a TGA binary linked into the kernel image via an assembly `incbin` stub (`_panic_tga_start` / `_panic_tga_size`). The image is decoded once at `init` time and stored in a pre-built LVGL image descriptor.

All text formatting in the panic path uses a set of internal buffer-writing helpers (`writeHexToBuffer`, `writeStrToBuffer`, `writeIntToBuffer`) that do not call the kernel string library, making the panic path robust against faults in those subsystems.

A compile-time switch `BSOD_ENABLE` gates the display path; if disabled, `panic` only writes to syslog and halts.

### gfxd Crash Detection

When `panic` is triggered, it checks whether the currently executing process is `gfxd` (the graphics daemon). If so, LVGL’s internal state may be corrupt (since `gfxd` drives the LVGL render pipeline), so the unit falls back to `showVESAFallbackScreen`. This procedure fills the screen with the BSOD background colour and renders all diagnostic sections using `driver.video.DrawString`, `driver.video.DrawHex`, and `driver.video.DrawInt` (which draw 8×16 bitmap font glyphs via `DrawPixel`). The layout mirrors the LVGL BSOD but uses a simpler single-column text format.

### Syslog Output

All five diagnostic sections are written to syslog in every panic, regardless of the display path:

1. **Fault Info** — fault identifier and human-readable description
2. **CPU Registers** — name/value pairs from the register snapshot
3. **Process Info** — name, PID, parent PID, state, and priority of the current process
4. **System Info** — kernel version, build date, compiler, revision, heap status, process count, uptime
5. **Call Stack** — frozen tracer output
