package view

import "core:fmt"
import "core:strings"
import "../sim"

SECONDS_PER_MINUTE :: 60
MINUTES_PER_HOUR :: 60
HOURS_PER_DAY :: 24
DAYS_PER_YEAR :: 365

SECONDS_PER_HOUR :: SECONDS_PER_MINUTE * MINUTES_PER_HOUR
SECONDS_PER_DAY :: SECONDS_PER_HOUR * HOURS_PER_DAY
SECONDS_PER_YEAR :: SECONDS_PER_DAY * DAYS_PER_YEAR

write_clockstring_from_seconds :: proc(b: ^strings.Builder, time: sim.Seconds) {
    _time := time
    years := _time / SECONDS_PER_YEAR
    _time -= years * SECONDS_PER_YEAR
    days := _time / SECONDS_PER_DAY
    _time -= days * SECONDS_PER_DAY
    hours := _time / SECONDS_PER_HOUR
    _time -= hours * SECONDS_PER_HOUR
    minutes := _time / SECONDS_PER_MINUTE
    _time -= minutes * SECONDS_PER_MINUTE
    seconds := _time

    fmt.sbprintf(b, "t+%2ds:%2dm:%2dh:%3dd:year %d", seconds, minutes, hours, days, years)
    // NOTE: better way to show large year value with exponentional notation, e.g. %.3e
}
