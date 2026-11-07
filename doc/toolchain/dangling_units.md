# Automatic boot-unit inclusion

Run the usual `docker compose build builder` and `docker compose run builder`
from Asuro. Only this repository is required. Compose and Drone use the same
Dockerfile and repository build context, producing `t3hn3rd/asuro-build:latest`.
The Dockerfile inherits the published `t3hn3rd/moderne-asuro-recipes:0.1.1` image,
pinned by digest. It already includes Java, Moderne CLI, the Pascal LST generator,
and the registered recipe. The Asuro layer installs FPC and the kernel build tools.

To upgrade tooling, publish the upstream images first and update `RECIPES_IMAGE`
in the Dockerfile to the new tag and digest. Local tooling image testing can use
`docker compose build --build-arg RECIPES_IMAGE=<local-tag> builder`.

`ASURO_ARCH` selects the source architecture, defaulting to `x86`. For example:

```sh
export ASURO_ARCH=x86
docker compose run --rm builder
```

Compose forwards this variable to the builder; Drone inherits it from its compile
environment. Only `src/arch/$ASURO_ARCH` is added to FPC's unit search paths.
Other architecture folders are excluded from LST generation and from the recipe's
dependency graph and results. Common units outside `src/arch` remain eligible.
The selected architecture folder must exist. This source selection does not
change the existing i386 compiler target, assembly stub, or linker settings;
an x86_64 port still needs those platform-specific changes.

`compile_dangling.sh` runs after Wasuro synchronization and before FPC. It copies
only `src/` and `compat/` into an isolated temporary analysis repository, generates
LSTs with rewrite-pascal, runs the standalone Moderne recipe, exports its
datatable, and writes `src/boot/dangling_units.inc`. Wasuro is not parsed.
Datatable conversion is provided by the standalone project's Java exporter.
Parse errors, recipe failures, and malformed datatables stop the build. The
generated include is ignored by Git and removed before each generation attempt.

Use `{$DEFINE NOT_DANGLING}` near a unit declaration to exclude an experimental
or legacy unit from automatic inclusion. It can still be referenced normally.
This is a file-level marker; conditional definitions are not evaluated. The
analysis follows both interface and implementation uses, without expanding
includes or evaluating conditional compilation.

Moderne runs through its CLI normally; any license or tenant configuration
required by your CLI installation must be provided to the container separately.
No host credentials are copied into the image.
