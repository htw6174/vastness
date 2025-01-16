package view

import sa "core:container/small_array"

import "../platform"

Mouse_Button :: enum u8 {
    LEFT = 0,
    RIGHT,
    MIDDLE,
    BUTTON_4,
    BUTTON_5,
}

Pointer :: struct {
    // TODO TEMP: would like mouse buttons, controller buttons, and keys to be handled the same way
    left, right: bool,
    x, y, dx, dy: i32,
    last_x, last_y: i32,
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
		if event.button.button == 1 do pointer.left = true
		if event.button.button == 3 do pointer.right = true
	case .MOUSEBUTTONUP:
	    // TODO
		if event.button.button == 1 do pointer.left = false
		if event.button.button == 3 do pointer.right = false
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
	pointer.x, pointer.y = platform.Get_Mouse_State()
	pointer.dx = pointer.x - pointer.last_x
	pointer.dy = pointer.y - pointer.last_y
	pointer.last_x = pointer.x
	pointer.last_y = pointer.y
}

register_keybind :: proc(keybind: Keybind) {
    sa.append(&keybinds, keybind)
}
