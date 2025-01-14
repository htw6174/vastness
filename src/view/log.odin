/*
Utilities for printing debug messages to any of: the screen, a platform-specific console, or a log file
*/
package view

import "../platform"

log :: proc(message: string) {
    logf(message)
}

logf :: proc(format: string, args: ..any) {
    platform.logf(format, ..args)
    // TODO: optionally print to log file
    // TODO: optionally print to screen
}
