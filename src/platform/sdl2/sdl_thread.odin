package sdl2


import c "vendor_c"

when ODIN_OS == .Windows {
//	foreign import lib "sdl2"
} else {
//	foreign import lib "sdl2"
}

Thread :: struct {}

threadID :: distinct c.ulong
TLSID :: distinct c.uint

ThreadPriority :: enum c.int {
	LOW,
	NORMAL,
	HIGH,
	TIME_CRITICAL,
}

ThreadFunction :: proc "c" (data: rawptr) -> c.int

@(default_calling_convention="c", link_prefix="SDL_")
foreign {
	CreateThread              :: proc(fn: ThreadFunction, name: cstring, data: rawptr) -> ^Thread ---
	CreateThreadWithStackSize :: proc(fn: ThreadFunction, name: cstring, stacksize: c.size_t, data: rawptr) -> ^Thread ---
	GetThreadName             :: proc(thread: ^Thread) -> cstring ---
	ThreadID                  :: proc() -> threadID ---
	GetThreadID               :: proc(thread: ^Thread) -> threadID ---
	SetThreadPriority         :: proc(priority: ThreadPriority) -> c.int ---
	WaitThread                :: proc(thread: ^Thread, status: ^c.int) ---
	DetachThread              :: proc(thread: ^Thread) ---
	TLSCreate                 :: proc() -> TLSID ---
	TLSGet                    :: proc(id: TLSID) -> rawptr ---
	TLSSet                    :: proc(id: TLSID, value: rawptr, destructor: proc "c" (rawptr)) -> c.int ---
	TLSCleanup                :: proc() ---
}