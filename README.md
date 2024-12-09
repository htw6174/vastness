Demo project for making games with Odin as either a native or wasm application. Trades the easy JS library access of Odin's `JS` target for the ability to use any c libraries that work with Emscripten, such as SDL or [Sokol](https://github.com/floooh/sokol).

Both native and wasm builds use WebGPU for the rendering backend. The intent is to quickly build and test natively, then deploy to web with minimal changes.

Thanks to [Caedo](https://github.com/Caedo/raylib_wasm_odin) for the Emscripten wrapper approach, and [NHDaly](https://github.com/NHDaly/sdl-wasm-odin) for modifying Odin's SDL2 package to work with Emscripten.

## Requirements
Only tested on linux, but the makefile's odin and emcc commands should also work on Windows or OSX

Both native and wasm builds require [Odin](https://odin-lang.org/)

Native builds require [wgpu-native](https://github.com/gfx-rs/wgpu-native)

Wasm builds require the Emscripten SDK

Running wasm builds requires a browser with WebGPU support: https://github.com/gpuweb/gpuweb/wiki/Implementation-Status

## Usage
(One-time) Build sokol_gfx to library files by running the `src/sokol/build_clibs_*` script for your os, and `src/sokol/build_clibs_wasm.sh` (TODO: add Windows build script for wasm)

In `src/main.odin`, uncomment the import block for the build type you want (native or wasm)
- Unfortunately, Odin's `when` compile-time conditional doesn't allow `include` statements, so you must either do this when changing build targets, OR only access platform-dependent modules through a [conditionally-compiled wrapper file](https://odin-lang.org/docs/overview/#file-suffixes)

Do `make native` or `make wasm` (default: native)

Start the app by running `build/game` for native builds, or hosting the contents of `web` for wasm builds e.g. `emrun web`

## Limitations / Future Improvements
Any c libraries used in wasm builds must work with the "freestanding" Odin target, and the object / source file with definitions must later be linked with emcc.
