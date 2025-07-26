package main
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal/ansi"

import ma "vendor:miniaudio"
import ray "vendor:raylib"
APP_NAME :: "Odin BytePusher"
MEMORY_SIZE :: 0x1000008
SCREEN_WIDTH :: 256
SCREEN_HEIGHT :: 256
FPS :: 60
AUDIO_SAMPLE_RATE :: 15360 // 256 * 60 frame.

CLEAR_SCREEN :: ansi.CSI + "2J" + ansi.CSI + ansi.CUP


min :: proc(a: f32, b: f32) -> f32 {
	if a < b {return a}
	return b
}

draw :: proc(pixelData: []u8, palette: []ray.Color) {
	for pixel, i in pixelData {
		ray.DrawPixel(i32(i % 256), i32(i / 256), palette[pixel])
	}
}

App :: struct {
	device:       ma.device,
	mutex:        sync.Mutex,
	wave_samples: [256]i8,
	noSound:      bool,
	fullScreen:   bool,
}
app: App

audio_callback :: proc(device: ^ma.device, output, input: rawptr, frame_count: u32) {
	if app.noSound {return}
	device_buffer := mem.slice_ptr((^f32)(output), 256) // get device buffer
	sync.lock(&app.mutex)
	for i in 0 ..< 256 {
		// values are -128 to 127 in float it needs to be -1 / + 1 (I think)
		device_buffer[i] = (f32)(app.wave_samples[i]) / 128
	}
	sync.unlock(&app.mutex)
}

// from my term2
colorize :: proc(text, color, bg_color: string) -> string {
	sb := strings.builder_make()
	strings.write_string(&sb, ansi.CSI)
	strings.write_string(&sb, color)
	strings.write_string(&sb, ansi.SGR)
	strings.write_string(&sb, ansi.CSI)
	strings.write_string(&sb, bg_color)
	strings.write_string(&sb, ansi.SGR)
	strings.write_string(&sb, text)
	strings.write_string(&sb, ansi.CSI)
	strings.write_string(&sb, ansi.RESET)
	strings.write_string(&sb, ansi.SGR)
	return strings.to_string(sb)
}

main :: proc() {
	if (len(os.args) < 2) {
		fmt.println(
			colorize(APP_NAME + " Error: ", ansi.FG_BRIGHT_RED, ansi.BOLD),
			"Need to pass a bytepusher memory file",
		)
		return
	}
	sbHelp := strings.builder_make()

	fmt.sbprintln(
		&sbHelp,
		CLEAR_SCREEN,
		colorize(APP_NAME + "\n", ansi.FG_BLUE, ansi.BG_BLACK),
		colorize("===============\n", ansi.FG_BRIGHT_BLUE, ansi.BG_BLACK),
		`

command: `,
		os.args[0],
		` path\\to\\romfile [`,
		colorize("--no-sound", ansi.FG_BRIGHT_WHITE, ansi.ITALIC),
		`] [`,
		colorize("--full", ansi.FG_BRIGHT_WHITE, ansi.ITALIC),
		`]

the `,
		colorize("--no-sound", ansi.FG_BRIGHT_WHITE, ansi.ITALIC),
		` option allows running a rom and skip sound reproduction (useful in case of wrong sounds)

the `,
		colorize("--full", ansi.FG_BRIGHT_WHITE, ansi.ITALIC),
		` option starts in full screen.
`,
		sep = "",
	)
	for i in 0 ..< len(os.args) {
		if os.args[i] == "-h" || os.args[i] == "--help" {
			fmt.println(strings.to_string(sbHelp))
			return
		}
		if os.args[i] == "--no-sound" {
			app.noSound = true
		}
		if os.args[i] == "--full" {
			app.fullScreen = true
		}
	}


	// set audio device settings
	result: ma.result

	device_config := ma.device_config_init(ma.device_type.playback)
	device_config.playback.format = ma.format.f32
	device_config.playback.channels = 1

	device_config.sampleRate = AUDIO_SAMPLE_RATE
	device_config.dataCallback = ma.device_data_proc(audio_callback)
	device_config.periodSizeInFrames = 256

	if (ma.device_init(nil, &device_config, &app.device) != .SUCCESS) {
		fmt.println("Failed to open playback device.")
		return
	}

	if (ma.device_start(&app.device) != .SUCCESS) {
		fmt.println("Failed to start playback device.")
		ma.device_uninit(&app.device)
		return
	}

	memory := make([]u8, MEMORY_SIZE)

	palette := make([]ray.Color, 256)
	for r in 0 ..< 6 {
		for g in 0 ..< 6 {
			for b in 0 ..< 6 {
				palette[r * 36 + g * 6 + b] = ray.Color{u8(r * 33), u8(g * 33), u8(b * 33), 255}
			}
		}
	}
	for i in 216 ..< 256 {
		palette[i] = ray.BLACK
	}

	data, ok := os.read_entire_file(os.args[1], context.allocator)
	for byte, i in data {
		memory[i] = byte
	}
	defer delete(data, context.allocator)
	defer delete(palette)
	defer delete(memory)

	flags: ray.ConfigFlags = {.WINDOW_RESIZABLE, .VSYNC_HINT}
	ray.SetConfigFlags(flags)
	ray.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, APP_NAME)
	if (app.fullScreen) {
		display := ray.GetCurrentMonitor()
		ray.SetWindowSize(ray.GetMonitorWidth(display), ray.GetMonitorHeight(display))
	}
	// Render texture initialization, used to hold the rendering result so we can easily resize it
	target := ray.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	ray.SetTextureFilter(target.texture, ray.TextureFilter.BILINEAR) // Texture scale filter to use

	ray.SetTargetFPS(60)

	scanArray := []ray.KeyboardKey {
		ray.KeyboardKey.V, // F
		ray.KeyboardKey.F, // E
		ray.KeyboardKey.R, // D
		ray.KeyboardKey.FOUR, // C
		ray.KeyboardKey.C, // B
		ray.KeyboardKey.Z, // A
		ray.KeyboardKey.D, // 9
		ray.KeyboardKey.S, // 8
		// --
		ray.KeyboardKey.A, // 7
		ray.KeyboardKey.E, // 6
		ray.KeyboardKey.W, // 5
		ray.KeyboardKey.Q, // 4
		ray.KeyboardKey.THREE, // 3
		ray.KeyboardKey.TWO, // 2
		ray.KeyboardKey.ONE, // 1
		ray.KeyboardKey.X, // 0
	}
	valueArray := []u8 {
		0b10000000,
		0b01000000,
		0b00100000,
		0b00010000,
		0b00001000,
		0b00000100,
		0b00000010,
		0b00000001,
	}

	for !ray.WindowShouldClose() {
		a: u8 = 0
		b: u8 = 0
		pc: u32 = (u32)(memory[2]) << 16 + (u32)(memory[3]) << 8 + (u32)(memory[4])

		for value, index in scanArray {
			if ray.IsKeyPressed(value) {
				if index < 8 {
					a += valueArray[index % 8]
				} else {
					b += valueArray[index % 8]
				}
			}
		}
		memory[0] = a
		memory[1] = b

		for i := 0; i < 0x10000; i += 1 {

			a: u32 = (u32)(memory[pc]) << 16 + (u32)(memory[pc + 1]) << 8 + (u32)(memory[pc + 2])
			b: u32 =
				(u32)(memory[pc + 3]) << 16 + (u32)(memory[pc + 4]) << 8 + (u32)(memory[pc + 5])
			c: u32 =
				(u32)(memory[pc + 6]) << 16 + (u32)(memory[pc + 7]) << 8 + (u32)(memory[pc + 8])
			if (b < 0x100000) {
				memory[b] = memory[a]
			}
			pc = c
		}

		ray.BeginTextureMode(target)
		ray.ClearBackground(ray.BLACK)
		gfxLoc: u32 = ((u32)(memory[5]) << 16)
		screenData := memory[gfxLoc:gfxLoc + 0x10000]
		draw(screenData, palette)
		ray.EndTextureMode()

		scale := min(
			(f32)(ray.GetScreenWidth() / SCREEN_WIDTH),
			(f32)(ray.GetScreenHeight() / SCREEN_HEIGHT),
		)

		ray.BeginDrawing()
		ray.ClearBackground(ray.BLACK)
		ray.DrawTexturePro(
			target.texture,
			(ray.Rectangle){0.0, 0.0, (f32)(target.texture.width), (f32)(-target.texture.height)},
			(ray.Rectangle) {
				((f32)(ray.GetScreenWidth()) - ((f32)(SCREEN_WIDTH * scale))) * 0.5,
				((f32)(ray.GetScreenHeight()) - ((f32)(SCREEN_HEIGHT * scale))) * 0.5,
				(f32)(SCREEN_WIDTH * scale),
				(f32)(SCREEN_HEIGHT * scale),
			},
			(ray.Vector2){0, 0},
			0.0,
			ray.WHITE,
		)
		ray.EndDrawing()

		sndLoc: u32 = ((u32)(memory[6]) << 16 + (u32)(memory[7]) << 8)
		sync.lock(&app.mutex)
		for i in 0 ..< 256 {
			app.wave_samples[i] = (i8)(memory[sndLoc + (u32)(i)])
		}
		sync.unlock(&app.mutex)
	}

	ma.device_stop(&app.device)
	ma.device_uninit(&app.device)
	ray.CloseWindow()
}
