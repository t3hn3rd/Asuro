# Wasuro dependency

For kernel builds, `toolchain/build.ps1` fetches the Wasuro WebAssembly runtime using a sparse checkout of the `develop` branch. It caches the Pascal sources from `src/wasm` under `build/vendor/wasuro/` and mirrors them into the selected build profile for FPC. The docs target builds independently of Wasuro.
