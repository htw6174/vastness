Template project for making games with Odin as either a native or wasm application. Trades the easy JS library access of Odin's `JS` target for the ability to use any c libraries that work with Emscripten, such as SDL or [Sokol](https://github.com/floooh/sokol).

## Requirements
Only tested on linux, but the makefile's odin and emcc commands should also work on Windows or OSX
Both native and wasm builds require [Odin](https://odin-lang.org/)
Wasm builds require the Emscripten SDK

## Usage
(One-time) Build sokol_gfx to library files by running `src/sokol/build_clibs_*` for the platforms you're building for

In `src/main.odin`, uncomment the import block for the build type you want (native or wasm)
- Unfortunately, Odin's `when` compile-time conditional doesn't allow `include` statements, so you must do this or only access platform-dependent modules through a [conditionally-compiled wrapper file](https://odin-lang.org/docs/overview/#file-suffixes)

Run `make native` or `make wasm` (default: native)

Start the app by running `build/game` for native builds, or hosting the contents of `web` for wasm builds e.g. `emrun web`

## Limitations / Future Improvements
Any c libraries used in wasm builds must work with the "freestanding" Odin target, and the object / source file with definitions must later be linked with emcc.
