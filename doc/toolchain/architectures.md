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

Add an entry to `Get-ArchitectureTable` in `toolchain/build.ps1`. The table drives both the Ninja graph and the stage commands. Each build uses `build/<arch>/<profile>/` so the new target has its own cache.

| Area | What to configure |
| --- | --- |
| Pascal | Set `PascalCompiler`, `PascalFlags`, and `PpuDump`. Use a PPUDump compatible with the compiler's PPU format. |
| Native objects | Set `CCompiler`, `CTargetFlags`, `Archiver`, and `SymbolReader`. The shared stages use these tools for LVGL, icons, and `INITFINAL`. |
| Assembly | Set `Assemble` to a function reference such as `${function:Build-X86Assembly}`. Ninja tracks `StubSource` and any recipe-specific `SplashSource`, `SplashAssets`, or `InterruptSource`. The x86 handler uses `Assembler` and `AssemblerFlags` to assemble both inputs. |
| Kernel link | Set `Linker`, `LinkerFlags`, `LinkerScript`, and `RuntimeFlags`. Match the entry symbol and memory layout to the boot stub. |
| Boot image | Set `PackageImage` to a function reference and `ImageSource` to the asset directory. The handler produces `Asuro.iso` in the build directory for the launcher to publish. Use `$null` for `PackageImage` while bringing up a compile-only target. |

Reuse the shared stages when the target's tools accept the same command syntax. If the target uses an assembler other than NASM, adapt the version query in Write-Version, which currently parses NASM's output for the kernel version record. Check the generated `INITFINAL` record against the target `system` unit, including the count field, function pointer widths, alignment, symbol spelling, and calling convention. Check that compiler runtime libraries and all linked objects use the same target ABI.

## 4. Verify and enable CI

Start with the kernel-only target. Replace `<target>` with the newly configured name.

```sh
docker compose build builder
docker compose run --rm builder compile --arch <target> --profile release
docker compose run --rm builder compile --arch <target> --profile test:complex
```

Check the ELF class and machine with the target binutils. Repeat an identical build and verify that Ninja has no work. Edit one unit, delete a temporary unit, and switch profiles to check that objects and initializer symbols stay isolated. Once packaging is ready, build the ISO and boot it on a matching VM or board. Check the bootloader handoff, serial output, and standard and complex boot tests. Add the target to `.drone.yml` after those checks pass. Keep each published architecture in a separate checkout or artifact job because ISO jobs publish the same root filename.

See the [build pipeline](compile.md) and [automatic boot-unit inclusion](boot-units.md) for the shared build rules.
