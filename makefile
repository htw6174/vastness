native:
	echo "odin build"
	mkdir -p build
	odin run src -define:SOKOL_WGPU=true -out:build/game -debug

wasm:
	echo "odin build object"
	mkdir -p build
	odin build src -target=freestanding_wasm32 -out:build/odin -build-mode:obj -debug -show-system-calls

	echo "emcc build"
	mkdir -p web
	cp index.html web/

	emcc src/main.c \
	build/odin.wasm.o \
	src/sokol/sokol_gfx.wasm \
	$(shell odin root)vendor/stb/lib/stb_rect_pack_wasm.o \
	$(shell odin root)vendor/stb/lib/stb_truetype_wasm.o \
	-g \
	-s WASM=1 \
	-s USE_SDL=2 \
	-s USE_WEBGPU=1 \
	-s INITIAL_MEMORY=128mb \
	-o web/game.js
