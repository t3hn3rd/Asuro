# Build Asuro with Docker, PowerShell and Ninja

Build the builder image from the repository root with `docker compose build builder`. The builder runs `toolchain/build.ps1` using PowerShell and keeps its build cache in the mounted repository. The script generates the Ninja graph inside the container.

```sh
docker compose run --rm builder compile --arch x86 --profile debug
docker compose run --rm builder iso --arch x86 --profile test:complex
docker compose run --rm builder iso --arch x86_64 --profile test:complex
docker compose run --rm builder docs
docker compose run --rm builder all --arch x86 --profile release
```

| Task | Result |
| --- | --- |
| `compile` | Build and link the kernel. |
| `iso` | Build the kernel as needed and package the ISO. |
| `docs` | Build the documentation under `build/docs/site/`. |
| `all` | Build the ISO and documentation. |

The default is `all --arch x86 --profile release`. The `x86` and `x86_64` recipes build i386 and AMD64 kernels respectively. Both package a BIOS GRUB ISO. See [Add a target architecture](architectures.md) for the compiler, linker, and boot recipes needed for another target.

| Profile | Configuration |
| --- | --- |
| `release` | Optimised kernel with stripped link output. |
| `debug` | Unoptimised kernel with debug symbols. |
| `test:minimal` | Optimised build with debug symbols and `UNIT_TESTS`. |
| `test:complex` | Minimal tests plus `UNIT_TESTS_COMPLEX`. |

`ASURO_ARCH`, `UNIT_TESTS`, and `COMPLEX_TESTS` can also set defaults. Explicit flags take precedence. Drone uses `release` on master and `test:complex` on other branches.

## Run boot tests in QEMU

```sh
docker compose run --rm builder iso --arch x86 --testonly
docker compose run --rm builder iso --arch x86 --profile test:complex --testonly
```

`--testonly` selects the standard test suite unless the effective profile is `test:complex`, which runs both suites. Test-only builds have separate caches. After printing the final test summary over COM1, the kernel requests power-off on a QEMU PC with SeaBIOS and ACPI enabled.

The standard suite was verified with 2 GiB of guest RAM. Run QEMU under a host-side timeout for regression testing.

```sh
qemu-system-i386 -machine pc -m 2048 -cdrom Asuro.iso -display none -serial stdio -monitor none -no-reboot
```

Require QEMU to exit and the final `tests run` summary to report a nonzero test count and zero failures. The guest requests power-off after the summary on both passing and failing runs.

## Build outputs

Kernel outputs, Pascal units, and Ninja state live under `build/<arch>/<profile>/`. An ISO build also copies the result to `Asuro.iso` for the existing VM launcher and CI. Profiles have separate compiler caches. The build uses `assets/iso/` as the ISO source tree and `assets/embedded/` for boot artwork and icon fonts. Wasuro and LVGL are cached under `build/vendor/`. Asuro’s LVGL integration sources live in `src/driver/video/lvgl/`.

The launcher refreshes its source inventory before starting Ninja. Deleted and moved units lose their cached objects and compiled units. Pascal inputs are checked by content. A changed unit is recompiled even if its size and timestamp match. FPC can reuse unaffected units. Changes to compiler options or shared includes trigger a full Pascal rebuild. The linker and `INITFINAL` generator use the same object list derived from FPC's compiled-unit dependencies starting at `asuro`. Native objects track headers through compiler-generated dependency files. The [boot-unit analysis](boot-units.md) still runs when Pascal sources change.
