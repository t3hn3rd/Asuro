# app.setres

Terminal command for changing the display resolution at runtime.

## Overview

`app.setres` registers the `SETRES` shell command, which switches the display to a specified width and height at 32 bits per pixel. It delegates to the GPU driver framework (`driver.video.gpu.setMode`), which attempts a BGA (Bochs Graphics Adapter) mode switch first and falls back to VBE/VESA if BGA is unavailable.

## Dependencies

- `io.stdio`, `io.syslog`
- `driver.video.gpu`
- `core.util`, `arch.x86.util`
- `core.strings`
- `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `SETRES` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Parses two numeric parameters (width and height). Validates that neither is zero. Calls `driver.video.gpu.setMode(w, h, 32, info)` and reports the active driver name on success, or an error message on failure.

Usage: `SETRES <width> <height>` (e.g. `SETRES 1024 768`)

## Notes

The bit depth is always fixed at 32. The `TGPUModeInfo` struct populated by `setMode` is not currently inspected by this command. A failed mode switch does not restore any previous state; behaviour depends on the underlying GPU driver.
