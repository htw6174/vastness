package view

import sa "core:container/small_array"

import "../platform"

Mouse_Button :: enum {
    LEFT = 1,
    RIGHT,
    MIDDLE,
    BUTTON_4,
    BUTTON_5,
}

Pointer :: struct {
    x, y, dx, dy: i32
}

Keybind :: struct {
    keycode: platform.Keycode,
    trigger: platform.Bind_Trigger,
    callback: proc(^State),
}

pointer: Pointer
// TODO: could implement this as a dictionary, allow creating other bindgroups and switching the active one
keybinds: sa.Small_Array(256, Keybind)

handle_event :: proc(event: ^platform.Event, user_data: rawptr) {
    state := (^State)(user_data)
    binds := sa.slice(&keybinds)
    #partial switch event.type {
    case .KEYDOWN:
        for bind in binds {
            if event.key.keysym.sym == bind.keycode { //&& event.type == sdl2.EventType(bind.trigger) {
                bind.callback(state)
           	}
        }
    // NOTE: only captures visible glyphs and non-newline whitespace
	case .TEXTINPUT:
		//s := string(cstring(raw_data(event.text.text[:])))
		input_text(state, event.text.text[:])
	case .MOUSEMOTION:
	    pointer.x = event.motion.x
		pointer.y = event.motion.y
		pointer.dx = event.motion.xrel
		pointer.dy = event.motion.yrel
	case .MOUSEBUTTONDOWN:
	    // TODO
	case .MOUSEBUTTONUP:
	    // TODO
	}
}

handle_input_state :: proc(state: ^State) {
    keyboard_state := platform.Get_Keyboard_State()
    binds := sa.slice(&keybinds)
    for bind in binds {
	    if bind.trigger == .HOLD {
			if keyboard_state[int(platform.scancode_from_keycode(bind.keycode))] > 0 {
			    bind.callback(state)
			}
		}
	}
}

register_keybind :: proc(keybind: Keybind) {
    sa.append(&keybinds, keybind)
}
