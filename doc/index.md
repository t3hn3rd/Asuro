# Asuro OS

Asuro is a 32-bit x86 operating system kernel written in Free Pascal and x86 assembly.

## Getting Started

Clone the repository, install Docker with Compose, and run the following from the repository root. The builder image supplies PowerShell, Ninja, Free Pascal and the boot-image tools.

```sh
docker compose build builder
```

| Command | Outcome |
| --- | --- |
| `docker compose run --rm builder iso` | Builds a bootable release ISO and publishes it as `Asuro.iso` at the repository root. |
| `docker compose run --rm builder iso --profile test:minimal` | Builds an ISO with standard boot tests enabled. |
| `docker compose run --rm builder iso --profile test:complex` | Builds an ISO with standard and complex boot tests enabled. |
| `docker compose run --rm builder compile --profile debug` | Builds and links a debug kernel at `build/x86/debug/kernel.bin`. |
| `docker compose run --rm builder docs` | Generates the documentation site at `build/docs/site/`. |
| `docker compose run --rm builder all` | Builds both the release ISO and documentation. |

The default architecture is `x86`. Profiles keep independent build caches under `build/<arch>/<profile>/`. See the [build pipeline](toolchain/compile.md) for details on incremental builds and profiles.

Boot the generated ISO as optical media in a BIOS-based VM. The repository includes a VirtualBox launcher at `tools/virtualbox-wrapper.ps1`.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/` | Kernel, architecture code, drivers, services, apps, and compatibility units. |
| `src/driver/video/lvgl/` | Asuro’s LVGL configuration and C integration. |
| `assets/embedded/` | Artwork and fonts compiled into the kernel. |
| `assets/iso/` | Files packaged into the boot image. |
| `toolchain/` | PowerShell build launcher, linker script, and icon generator. |
| `tools/` | Developer utilities, including the VirtualBox launcher. |
| `doc/` | Documentation source, organised by the corresponding source area. |
| `build/` | Generated artifacts, dependency caches, build logs, and the docs site. |
