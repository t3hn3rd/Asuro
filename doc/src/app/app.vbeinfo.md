# app.vbeinfo

Terminal command for displaying current display mode parameters.

## Overview

`app.vbeinfo` registers the `VBEINFO` shell command, which prints the current framebuffer width, height, and bits-per-pixel as reported by `driver.video`. Despite the name it works with any registered video driver, not exclusively VESA/VBE.

## Dependencies

- `io.stdio`
- `driver.video`
- `core.util`, `arch.x86.util`
- `core.strings`
- `debug.tracer`

## Functions and Procedures

### init

```pascal
procedure init();
```

Registers the `VBEINFO` command with `io.stdio`.

### run (internal)

```pascal
procedure run(Params: PParamList; stdin_buf, stdout_buf, stderr_buf: POutBuf);
```

Command entry point. Writes three lines to `stdout_buf`:

- `Pixel Width: <value>`
- `Pixel Height: <value>`
- `Bits Per Pixel: <value>`

Values are read from `driver.video.frontBufferWidth`, `frontBufferHeight`, and `frontBufferBpp`.
