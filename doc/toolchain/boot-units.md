# Automatic boot-unit inclusion

Before FPC runs, the `boot-units` stage in `toolchain/build.ps1` copies the selected source tree into a temporary repository and runs the Moderne Pascal analysis. The exporter writes `dangling_units.inc` into the profile’s source mirror at `build/<arch>/<profile>/source/src/boot/`. Wasuro is outside the analysis roots. The generated include changes only when its contents change.

Use `{$DEFINE NOT_DANGLING}` near a unit declaration to exclude an experimental or legacy unit from automatic inclusion. It can still be referenced normally. This is a file-level marker; conditional definitions are not evaluated. The analysis follows both interface and implementation uses, without expanding includes or evaluating conditional compilation.

On success the build prints one line with the number of units and the generated include path. The full analysis log is saved as `build/<arch>/<profile>/boot-units.log`. On failure the build prints the end of that log and stops.
