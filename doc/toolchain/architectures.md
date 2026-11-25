# Add a target architecture

The builder runs on Linux in Docker. A target recipe selects the guest architecture, compiler, object format, and boot path. The existing `x86` recipe builds an i386 kernel and a BIOS GRUB ISO. Use it as the working reference when adding another target.

## 1. Add the target sources

1. Choose a lower-case target name and put its platform units under `src/arch/<target>/`.
2. Provide the target's kernel entry stub, runtime `system` unit, interrupt and memory code, and boot handoff. Audit shared units for direct x86 imports and assembly before treating them as portable.
3. Keep target-specific units out of other targets' compiler search paths. The launcher mirrors the selected architecture plus common sources. The boot-unit generator receives the same architecture name so it can analyse the same source set.

## 2. Add tools to the builder image

Update `Dockerfile` with the target-capable FPC compiler and any cross assembler, C compiler, binutils, and boot-image packages. The tools themselves must run on the builder host. The objects they emit must all use the target architecture and ABI.

For the native code, use the same target C compiler for LVGL, generated icons and `INITFINAL`. Resolve any compiler runtime library with that compiler. Verify the linker can read the compiler's objects and archives. Rebuild the image with `docker compose build builder` whenever the installed tools change.

## 3. Wire the recipe into the launcher

Make these changes in `toolchain/build.ps1`:

| Area | What to change |
| --- | --- |
| Target selection | Extend `Invoke-Build` and `Invoke-Stage` validation for the new architecture. Keep the architecture in `build/<arch>/<profile>/` so caches stay isolated. |
| Pascal | Select the target compiler and flags in `Get-PascalOptions` and `Build-Pascal`. Record the selected compiler version and effective options in `toolchain.json` so a toolchain change invalidates the Pascal cache. Use a `ppudump` compatible with the compiler’s PPU format. |
| Assembly | Update the `stub` and `splash` stages and their inputs in `Write-Graph`. The current splash assets are assembled with NASM using an x86 ELF format. Supply a target assembler or another way to embed those bytes for a different CPU family. |
| Native objects | Select the target C compiler, archive tool, and flags for the Ninja `cc` rule and the `icons`, `lvgl`, and `initcalls` stages. Keep compiler-generated header dependencies enabled. |
| Kernel link | Add a target linker script and select the linker, emulation, and runtime library in `Link-Kernel`. Add the selected linker script as a Ninja input. Match the entry symbol and memory layout to the boot stub. |
| Initialization | Check the generated `INITFINAL` record against the target `system` unit. Verify the count field, function pointer widths, alignment, symbol spelling, and calling convention. Use the compiler-derived object list for both symbol discovery and linking. |
| Boot image | Add the target's packaging recipe and asset dependencies. Only expose `iso` and `all` for that target once they can produce the expected boot image. Preserve the root `Asuro.iso` contract for CI jobs that publish ISOs. |

## 4. Verify and enable CI

Start with the kernel-only target. Replace `<target>` with the newly configured name.

```sh
docker compose build builder
docker compose run --rm builder compile --arch <target> --profile release
docker compose run --rm builder compile --arch <target> --profile test:complex
```

Check the ELF class and machine with the target binutils. Repeat an identical build and verify that Ninja has no work. Edit one unit, delete a temporary unit, and switch profiles to check that objects and initializer symbols stay isolated. Once packaging is ready, build the ISO and boot it on a matching VM or board. Check the bootloader handoff, serial output, and standard and complex boot tests. Add the target to `.drone.yml` after those checks pass. Keep each published architecture in a separate checkout or artifact job because ISO jobs publish the same root filename.

See the [build pipeline](compile.md) and [automatic boot-unit inclusion](boot-units.md) for the shared build rules.
