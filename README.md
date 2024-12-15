Space space space (more details later).

Platform and rendering support using SDL2 and [Sokol](https://github.com/floooh/sokol).

Both native and wasm builds use WebGPU for the rendering backend. The intent is to quickly build and test natively, then deploy to web with minimal changes.

Thanks to [Caedo](https://github.com/Caedo/raylib_wasm_odin) for the Emscripten wrapper approach, and [NHDaly](https://github.com/NHDaly/sdl-wasm-odin) for modifying Odin's SDL2 package to work with Emscripten.

## Requirements
Only tested on linux, but the makefile's odin and emcc commands should also work on Windows or OSX

Both native and wasm builds require [Odin](https://odin-lang.org/)

Native builds require [wgpu-native](https://github.com/gfx-rs/wgpu-native)

Wasm builds require the Emscripten SDK

Running wasm builds requires a browser with WebGPU support: https://github.com/gpuweb/gpuweb/wiki/Implementation-Status
- As of December 2024: Chrome on Windows, Chrome with experimental flags enabled on Linux, or any firefox nightly release

## Usage
(One-time) Build sokol_gfx to library files by running the `src/sokol/build_clibs_*` script for your os, and `src/sokol/build_clibs_wasm.sh` (TODO: add Windows build script for wasm)
- Linux: `cd src/sokol` then `./build_clibs_linux.sh` and/or `./build_clibs_wasm.sh`

(One-time) (Only required for wasm builds) Copy the contents of `patch` into your `odin root` directory
- Linux: `cp -r patch/* $(odin root)`
- This changes some vendor libs which normally require Odin's libc for wasm to ignore the requirement, using emscripten's libc instead
- Also adds unimplemented definitions for `core:os` procs on freestanding builds, similar to JS

Do `make native` or `make wasm` (default: native)

Start the app by running `build/game` for native builds, or hosting the contents of `web` for wasm builds e.g. `emrun web`

## Limitations / Future Improvements
Any c libraries used in wasm builds must work with the "freestanding" Odin target, and the object / source file with definitions must later be linked with emcc.
