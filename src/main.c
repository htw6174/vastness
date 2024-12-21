#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
#define SOKOL_LOG_IMPL
#include "sokol/c/sokol_log.h"

extern void start();
extern void step();
extern void stop();

int main() {
    start();

    emscripten_set_main_loop(step, -1, 1);

    stop();
    return 0;
}

void get_canvas_size(double *width, double *height) {
    // Factors in display dpi and browser zoom level. Multiplying with css size ensures constant framebuffer size at any zoom level.
    double scale = emscripten_get_device_pixel_ratio();
    emscripten_get_element_css_size("#canvas", width, height);
    *width *= scale;
    *height *= scale;
}
