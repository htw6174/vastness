set -e

build_lib_wasm32_release() {
    src=$1
    dst=$2
    backend=$3
    echo $dst
    cc -pthread -c -O2 -DNDEBUG -DIMPL -D__EMSCRIPTEN__ -D$backend -I$HOME/include/emsdk/upstream/emscripten/cache/sysroot/include c/$src.c
    ar rcs $dst.a $src.o
}

build_lib_wasm32_debug() {
    src=$1
    dst=$2
    backend=$3
    echo $dst
    cc -pthread -c -g -DIMPL -D__EMSCRIPTEN__ -D$backend -I$HOME/include/emsdk/upstream/emscripten/cache/sysroot/include c/$src.c
    emcc -pthread -c -g -sSIDE_MODULE=1 -DIMPL -D$backend c/$src.c -o $src.wasm
    ar rcs $dst.a $src.o
}

# wasm32 + WebGPU + Release
# build_lib_wasm32_release sokol_log         gfx/sokol_log_wasm_x32_wgpu_release SOKOL_WGPU
build_lib_wasm32_release sokol_gfx         gfx/sokol_gfx_wasm_x32_wgpu_release SOKOL_WGPU
# build_lib_wasm32_release sokol_app         gfx/sokol_app_wasm_x32_wgpu_release SOKOL_WGPU
# build_lib_wasm32_release sokol_glue        gfx/sokol_glue_wasm_x32_wgpu_release SOKOL_WGPU

# wasm32 + WebGPU + Debug
# build_lib_wasm32_debug sokol_log         gfx/sokol_log_wasm_x32_wgpu_debug SOKOL_WGPU
build_lib_wasm32_debug sokol_gfx         gfx/sokol_gfx_wasm_x32_wgpu_debug SOKOL_WGPU
# build_lib_wasm32_debug sokol_app         gfx/sokol_app_wasm_x32_wgpu_debug SOKOL_WGPU
# build_lib_wasm32_debug sokol_glue        gfx/sokol_glue_wasm_x32_wgpu_debug SOKOL_WGPU

rm *.o
