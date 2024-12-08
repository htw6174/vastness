#include <emscripten/emscripten.h>
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
