# WebGPU Support for WASM Applications

## Overview

Asuro provides WebGPU API compatibility for WASM applications. Apps compiled
against the standard `webgpu.h` C API can create GPU resources, build render
pipelines, and issue draw calls. The host implements these as WASM host
functions backed by a software rasterizer.

## Architecture

```
WASM App (imports webgpu.h functions)
    │
    ▼
WASURO Host Functions (module: "webgpu")
    │  Pop params from operand stack
    │  Read structs from WASM linear memory
    │  Dispatch to backend
    ▼
AsuroGPU Software Backend (Pascal)
    │  Handle table (devices, buffers, textures, pipelines)
    │  Command encoder → command buffer recording
    │  Software triangle rasterizer
    ▼
Host Framebuffer (PRGB32)
    │
    ▼
LVGL lv_image widget in Window Manager
    │
    ▼
Double-buffered display (SSE memcpy)
```

WASM applications import `webgpu.h` functions. WASURO resolves these to
Pascal host functions registered under the `"webgpu"` module (and `"env"`
for Emscripten compatibility). Each function pops parameters from the WASM
operand stack, reads descriptor structs from WASM linear memory, and
dispatches to the AsuroGPU software backend.

All WebGPU objects are opaque handles managed in a per-process handle table.
Surfaces bind to LVGL windows via `lv_image` widgets displaying host-side
BGRA framebuffers.

## Handle System

All WebGPU objects are opaque integer handles. Each WASM process gets its
own handle table stored on `TProcessWASMShim.GpuState`:

```pascal
TGPUHandleKind = (hkNone, hkInstance, hkAdapter, hkDevice, hkQueue,
                  hkSurface, hkBuffer, hkTexture, hkTextureView,
                  hkSampler, hkShaderModule, hkBindGroupLayout,
                  hkBindGroup, hkPipelineLayout, hkRenderPipeline,
                  hkCommandEncoder, hkRenderPassEncoder, hkCommandBuffer);

TGPUHandle = record
    Kind    : TGPUHandleKind;
    Ptr     : pointer;
    InUse   : boolean;
end;

TGPUHandleTable = record
    Handles : array[0..255] of TGPUHandle;
    Count   : uint32;
end;
```

## Rendering Pipeline

The software rasterizer executes recorded command buffers:

1. Vertex fetch from host-side GPU buffers
2. Vertex transform (4x4 matrix from uniform buffer)
3. Perspective divide and viewport transform
4. Triangle assembly per primitive topology
5. Backface culling
6. Scanline rasterization with edge walking
7. Texture sampling (nearest-neighbor) or vertex color interpolation
8. Depth test (16-bit Z-buffer)
9. Alpha/additive blending
10. Pixel write to surface framebuffer (BGRA)

## Shader Support

Initially, shaders are stored but not interpreted. The rasterizer uses a
fixed-function pipeline: vertex transform via MVP matrix (bind group 0,
binding 0), fragment color from texture sample or vertex color.

A future phase adds a WGSL subset interpreter for basic vertex/fragment
shaders.

## Implementation Phases

### Phase 1: Foundation

Handle system, instance/adapter/device creation, surface/window binding.

**WebGPU functions:**
- `wgpuCreateInstance` — Allocate instance record, return handle
- `wgpuInstanceRequestAdapter` — Allocate adapter, invoke callback synchronously
- `wgpuAdapterRequestDevice` — Allocate device + queue, invoke callback
- `wgpuDeviceGetQueue` — Return queue handle from device record
- `wgpuInstanceCreateSurface` — Create window via window manager, create LVGL
  `lv_image` widget, allocate host framebuffer, return surface handle
- `wgpuSurfaceConfigure` — Read configuration from WASM memory, resize FB
- `wgpuSurfaceGetCurrentTexture` — Write surface texture handle to WASM memory
- `wgpuSurfacePresent` — Copy host FB to LVGL image, invalidate widget
- `wgpuTextureCreateView` — Return texture view handle
- `wgpu*Release` — Free resource, mark handle slot unused

**Surface record:**
```pascal
TGPUSurface = record
    WinID      : uint32;        // Window manager slot
    FBWidth    : uint32;
    FBHeight   : uint32;
    HostFB     : PRGB32;        // Host-side BGRA pixel buffer
    DepthBuf   : puint16;       // 16-bit Z-buffer
    ImgWidget  : Plv_obj;       // LVGL image widget
    ImgDsc     : PLVImageDsc;   // lv_image_dsc_t (reuse boot.splash.pas pattern)
    SurfaceTex : uint32;        // Handle to surface texture
end;
```

### Phase 2: Buffers, Textures, Shader Modules

Create GPU resources that feed into the render pipeline.

**WebGPU functions:**
- `wgpuDeviceCreateBuffer` — Read descriptor, kalloc host buffer
- `wgpuQueueWriteBuffer` — Copy from WASM linear memory to host buffer
- `wgpuBufferGetMappedRange` — Return WASM-accessible pointer
- `wgpuBufferUnmap` — Sync mapped data back to host
- `wgpuDeviceCreateTexture` — Allocate host-side pixel buffer
- `wgpuQueueWriteTexture` — Copy pixel data from WASM to host texture
- `wgpuDeviceCreateSampler` — Store sampling parameters
- `wgpuDeviceCreateShaderModule` — Store WGSL source as opaque blob

**Buffer record:**
```pascal
TGPUBuffer = record
    Data    : pointer;    // kalloc'd host buffer
    Size    : uint32;
    Usage   : uint32;     // WGPUBufferUsage flags
    Mapped  : boolean;
    MapPtr  : uint32;     // WASM-side address if mapped
end;
```

**Texture record:**
```pascal
TGPUTexture = record
    Pixels  : pointer;    // kalloc'd pixel data
    Width   : uint32;
    Height  : uint32;
    Format  : uint32;     // WGPUTextureFormat enum
    BPP     : uint32;     // Bytes per pixel
    Usage   : uint32;
end;
```

### Phase 3: Render Pipeline & Bind Groups

Create render pipelines and bind resource groups.

**WebGPU functions:**
- `wgpuDeviceCreateBindGroupLayout` — Parse entry descriptors
- `wgpuDeviceCreateBindGroup` — Bind concrete resources to layout slots
- `wgpuDeviceCreatePipelineLayout` — Group bind group layouts
- `wgpuDeviceCreateRenderPipeline` — Parse `WGPURenderPipelineDescriptor`
  from WASM memory: vertex layout, primitive topology, depth/stencil state,
  blend state, multisample

**Pipeline record:**
```pascal
TGPURenderPipeline = record
    VertexShader    : uint32;
    FragmentShader  : uint32;
    VertexLayout    : TVertexLayout;
    Topology        : uint32;       // triangle-list, triangle-strip, etc.
    CullMode        : uint32;       // none, front, back
    FrontFace       : uint32;       // ccw, cw
    DepthTest       : boolean;
    DepthWrite      : boolean;
    DepthCompare    : uint32;
    BlendEnabled    : boolean;
    BlendSrc        : uint32;
    BlendDst        : uint32;
    PipelineLayout  : uint32;
end;

TVertexAttribute = record
    Format     : uint32;    // float32x2, float32x3, float32x4, etc.
    Offset     : uint32;
    ShaderLoc  : uint32;
end;

TVertexLayout = record
    Stride     : uint32;
    StepMode   : uint32;    // vertex, instance
    AttrCount  : uint32;
    Attrs      : array[0..15] of TVertexAttribute;
end;
```

**Parsing WASM structs:** WebGPU descriptors are deeply nested C structs.
The host reads them field-by-field from WASM linear memory using
`read_uint32`/`read_uint64`. Pointer fields are WASM addresses that must
be dereferenced via `wasm.types.heap`. Each struct must be documented with
exact field offsets for the 32-bit ABI.

### Phase 4: Command Encoding & Draw Calls

Record and execute render commands.

**WebGPU functions:**
- `wgpuDeviceCreateCommandEncoder` — Allocate command list
- `wgpuCommandEncoderBeginRenderPass` — Read render pass descriptor, begin
  recording
- `wgpuRenderPassEncoderSetPipeline` — Record pipeline bind
- `wgpuRenderPassEncoderSetVertexBuffer` — Record VB bind
- `wgpuRenderPassEncoderSetIndexBuffer` — Record IB bind
- `wgpuRenderPassEncoderSetBindGroup` — Record bind group
- `wgpuRenderPassEncoderDraw` — Record draw command
- `wgpuRenderPassEncoderDrawIndexed` — Record indexed draw
- `wgpuRenderPassEncoderSetViewport` — Record viewport
- `wgpuRenderPassEncoderSetScissorRect` — Record scissor
- `wgpuRenderPassEncoderEnd` — Finish recording
- `wgpuCommandEncoderFinish` — Produce command buffer
- `wgpuQueueSubmit` — Execute all recorded commands via software rasterizer

**Command buffer:**
```pascal
TGPUCommandKind = (cmdSetPipeline, cmdSetVertexBuffer, cmdSetIndexBuffer,
                   cmdSetBindGroup, cmdDraw, cmdDrawIndexed,
                   cmdSetViewport, cmdSetScissor, cmdClearColor,
                   cmdClearDepth);

TGPUCommand = record
    Kind : TGPUCommandKind;
    // Variant fields per command kind
end;

TGPUCommandBuffer = record
    Commands : array[0..1023] of TGPUCommand;
    Count    : uint32;
end;
```

### Phase 5: Software Rasterizer

Execute draw commands by software-rendering triangles to the surface
framebuffer.

**Rasterizer stages:**
1. **Vertex fetch** — Read raw bytes from host buffer per vertex attribute
   format (float32x2, float32x3, float32x4, unorm8x4)
2. **Vertex transform** — Multiply by 4x4 MVP matrix from uniform buffer
   (bind group 0, binding 0). Identity if no bind group bound.
3. **Viewport transform** — NDC to screen coordinates
4. **Triangle assembly** — Group vertices per primitive topology
5. **Backface culling** — Per pipeline cull mode setting
6. **Scanline rasterization** — Sort vertices by Y, split into flat-top /
   flat-bottom, walk scanlines interpolating X, depth, UV, color
7. **Texture sampling** — Nearest-neighbor (bilinear as stretch goal)
8. **Depth test** — 16-bit Z-buffer per pipeline depth settings
9. **Blending** — Alpha/additive per pipeline blend state
10. **Pixel write** — Store BGRA to surface HostFB

**Performance target:** ~1000 triangles at 160x120 at ~10-15 FPS. All math
runs as native Pascal, not interpreted WASM.

### Phase 6 (Stretch): WGSL Shader Interpreter

Parse and interpret a common WGSL subset instead of fixed-function fallback.

**Supported subset:**
- Vertex shaders: matrix multiply, passthrough varyings
- Fragment shaders: solid color, texture sample, vertex color passthrough
- Types: `vec2f`, `vec3f`, `vec4f`, `mat4x4f`, `f32`, `u32`
- Built-ins: `textureSample`, `normalize`, `dot`, `cross`, `clamp`
- Decorators: `@vertex`, `@fragment`, `@binding`, `@group`, `@location`,
  `@builtin`

**Approach:** Tokenize → simple AST → interpret per-vertex/per-fragment
during rasterization.

## Source Layout

All GPU-related code lives under `src/app/wasm/gpu/`:

| File | Phase | Purpose |
|------|-------|---------|
| `app.wasm.gpu.pas` | 1 | Main unit, handle table, init/cleanup |
| `app.wasm.gpu.types.pas` | 1 | Records, enums, constants matching webgpu.h |
| `app.wasm.gpu.instance.pas` | 1 | Instance/adapter/device host functions |
| `app.wasm.gpu.surface.pas` | 1 | Surface/window/present host functions |
| `app.wasm.gpu.buffer.pas` | 2 | Buffer creation, mapping, writes |
| `app.wasm.gpu.texture.pas` | 2 | Texture/sampler/view creation |
| `app.wasm.gpu.shader.pas` | 2 | Shader module storage (stub parser) |
| `app.wasm.gpu.pipeline.pas` | 3 | Pipeline, bind group, layout creation |
| `app.wasm.gpu.structs.pas` | 3 | WASM struct readers (descriptor parsing) |
| `app.wasm.gpu.encoder.pas` | 4 | Command encoder, render pass encoder |
| `app.wasm.gpu.submit.pas` | 4 | Command dispatch to rasterizer |
| `app.wasm.gpu.raster.pas` | 5 | Scanline triangle rasterizer |
| `app.wasm.gpu.math.pas` | 5 | Vec3/Vec4/Mat4 math utilities |
| `shader/app.wasm.gpu.shader.lexer.pas` | 6 | WGSL tokenizer |
| `shader/app.wasm.gpu.shader.parser.pas` | 6 | WGSL AST parser |
| `shader/app.wasm.gpu.shader.interp.pas` | 6 | WGSL per-vertex/fragment interpreter |

Modified existing files:
- `src/app/wasm/app.wasm.shim.pas` — Add `GpuState` field
- `src/app/wasm/app.wasm.runner.pas` — Register `webgpu` module host functions
- `src/app/wasm/app.wasm.cleanup.pas` — Free GPU resources on process exit

## WASM Module Naming

Host functions are registered under both `"webgpu"` and `"env"` modules for
Emscripten compatibility:

```pascal
wasm_register_host_func(ctx, 'webgpu', 'wgpuCreateInstance', @gpu_create_instance);
wasm_register_host_func(ctx, 'env', 'wgpuCreateInstance', @gpu_create_instance);
```

## Reused Patterns

- `boot.splash.pas` `buildImageDsc` — TLVImageDsc for raw pixel → lv_image
- `app.wasm.io.pas` ActiveShimPtr — safe host function context access
- `app.wasm.io.pas` `asuro_wasi_args_get` — TWASMHostFunc stack pop/push
- `driver.video.windows.pas` `createWindow` / `setWindowOwner` — window lifecycle
- `wasm.types.heap` `read_uint32` / `write_uint32` — page-aware memory access
