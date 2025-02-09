set -e

build_lib_x64_release() {
    src=$1
    dst=$2
    backend=$3
    echo $dst
    cc -pthread -c -O2 -DNDEBUG -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

build_lib_x64_debug() {
    src=$1
    dst=$2
    backend=$3
    echo $dst
    cc -pthread -c -g -DIMPL -D$backend c/$src.c
    ar rcs $dst.a $src.o
}

# x64 + GL + Release
build_lib_x64_release sokol_log         log/sokol_log_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_gfx         gfx/sokol_gfx_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_app         app/sokol_app_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_glue        glue/sokol_glue_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_time        time/sokol_time_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_audio       audio/sokol_audio_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_debugtext   debugtext/sokol_debugtext_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_shape       shape/sokol_shape_linux_x64_gl_release SOKOL_GLCORE
build_lib_x64_release sokol_gl          gl/sokol_gl_linux_x64_gl_release SOKOL_GLCORE

# x64 + GL + Debug
build_lib_x64_debug sokol_log           log/sokol_log_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_gfx           gfx/sokol_gfx_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_app           app/sokol_app_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_glue          glue/sokol_glue_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_time          time/sokol_time_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_audio         audio/sokol_audio_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_debugtext     debugtext/sokol_debugtext_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_shape         shape/sokol_shape_linux_x64_gl_debug SOKOL_GLCORE
build_lib_x64_debug sokol_gl            gl/sokol_gl_linux_x64_gl_debug SOKOL_GLCORE

# x64 + WGPU + Release
build_lib_x64_release sokol_gfx         gfx/sokol_gfx_linux_x64_wgpu_release SOKOL_WGPU

# x64 + WGPU + Debug
build_lib_x64_debug sokol_gfx         gfx/sokol_gfx_linux_x64_wgpu_debug SOKOL_WGPU

rm *.o
