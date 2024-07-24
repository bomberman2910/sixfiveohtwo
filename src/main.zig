const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const processor = @import("./cpu.zig");
const disassembler = @import("./disassembler.zig");
const terminal = @import("./terminal.zig");
const busdevice = @import("./busdevice.zig");

const stream = std.io.fixedBufferStream;

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 480;
const FRAME_TICKS = 17;

const NUMBER_INDEX_START = 48;
const COLON_INDEX = 58;
const SPACE_INDEX = 32;

var character_set: [128][8]u8 = undefined;
var terminal_screen = terminal.TerminalScreen.init();

pub fn main() !void {
    const character_rom = @embedFile("charmap.rom");
    var character_stream = stream(character_rom);
    var i: u8 = 0;
    while (i < 128) : (i += 1) {
        var character: [8]u8 = undefined;
        _ = try character_stream.read(&character);
        character_set[i] = character;
    }

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_OPENGL) orelse {
        sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
        sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGBA8888, sdl.SDL_TEXTUREACCESS_STATIC, WINDOW_WIDTH, WINDOW_HEIGHT) orelse {
        sdl.SDL_Log("Unable to create texture: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyTexture(texture);

    var framebuffer = [_]u32{255} ** (WINDOW_WIDTH * WINDOW_HEIGHT);
    var next_frame = sdl.SDL_GetTicks() + FRAME_TICKS;
    var quit = false;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var keyboard_state: [512]bool = [_]bool{false} ** 512;

    var cpu = processor.Cpu.init(allocator);
    defer cpu.deinit();

    // RAM
    try cpu.bus.addDevice(0x0000, 0x4000, null, false);
    // ROM
    try cpu.bus.addDevice(0xFF00, 0x0100, null, true);
    try cpu.bus.writeToDevice(0xFF00, @embedFile("monitor.rom"));
    // PIA
    try cpu.bus.addDevice(0xD010, 0x0004, pia_clock, false);
    // BASIC ROM
    try cpu.bus.addDevice(0xE000, 0x1000, null, true);
    try cpu.bus.writeToDevice(0xE000, @embedFile("basic.rom"));

    var is_key_press_handled = false;
    var is_cpu_running = false;

    while (!quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                sdl.SDL_KEYDOWN => {
                    keyboard_state[@intCast(event.key.keysym.scancode)] = true;
                },
                sdl.SDL_KEYUP => {
                    keyboard_state[@intCast(event.key.keysym.scancode)] = false;
                    is_key_press_handled = false;
                },

                else => {},
            }
        }

        const is_monitor_ready_for_input = try cpu.bus.read(0xD011) & 0x80 != 0x80;

        if (!is_key_press_handled) {
            // emulator control
            if (keyboard_state[sdl.SDL_SCANCODE_F5]) {
                try cpu.reset();
                is_key_press_handled = true;
            } else if (keyboard_state[sdl.SDL_SCANCODE_F10]) {
                if (!is_cpu_running)
                    try cpu.clock();
                is_key_press_handled = true;
            } else if (keyboard_state[sdl.SDL_SCANCODE_F11]) {
                is_cpu_running = !is_cpu_running;
                is_key_press_handled = true;
            }
            // hex characters
            else if (keyboard_state[sdl.SDL_SCANCODE_0] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey(')', &cpu);
                } else {
                    is_key_press_handled = try pressKey('0', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_1] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('!', &cpu);
                } else {
                    is_key_press_handled = try pressKey('1', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_2] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('@', &cpu);
                } else {
                    is_key_press_handled = try pressKey('2', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_3] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('#', &cpu);
                } else {
                    is_key_press_handled = try pressKey('3', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_4] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('$', &cpu);
                } else {
                    is_key_press_handled = try pressKey('4', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_5] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('%', &cpu);
                } else {
                    is_key_press_handled = try pressKey('5', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_6] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('^', &cpu);
                } else {
                    is_key_press_handled = try pressKey('6', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_7] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('&', &cpu);
                } else {
                    is_key_press_handled = try pressKey('7', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_8] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('*', &cpu);
                } else {
                    is_key_press_handled = try pressKey('8', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_9] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('(', &cpu);
                } else {
                    is_key_press_handled = try pressKey('9', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_A] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('A', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_B] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('B', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_C] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('C', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_D] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('D', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_E] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('E', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_F] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('F', &cpu);
            }
            // remaining letters
            else if (keyboard_state[sdl.SDL_SCANCODE_G] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('G', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_H] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('H', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_I] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('I', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_J] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('J', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_K] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('K', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_L] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('L', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_M] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('M', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_N] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('N', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_O] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('O', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_P] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('P', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_Q] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Q', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_R] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('R', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_S] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('S', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_T] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('T', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_U] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('U', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_V] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('V', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_W] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('W', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_X] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('X', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_Y] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Y', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_Z] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Z', &cpu);
            }
            // control keys and special characters
            else if (keyboard_state[sdl.SDL_SCANCODE_BACKSPACE] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('_', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_EQUALS] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('+', &cpu);
                } else {
                    is_key_press_handled = try pressKey('=', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_MINUS] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('_', &cpu);
                } else {
                    is_key_press_handled = try pressKey('-', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_SLASH] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('?', &cpu);
                } else {
                    is_key_press_handled = try pressKey('/', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_COMMA] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('<', &cpu);
                } else {
                    is_key_press_handled = try pressKey(',', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_SPACE] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(' ', &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_PERIOD] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('>', &cpu);
                } else {
                    is_key_press_handled = try pressKey('.', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_SEMICOLON] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey(':', &cpu);
                } else {
                    is_key_press_handled = try pressKey(';', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_APOSTROPHE] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('"', &cpu);
                } else {
                    is_key_press_handled = try pressKey('\'', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_LEFTBRACKET] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('{', &cpu);
                } else {
                    is_key_press_handled = try pressKey('[', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_RIGHTBRACKET] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('}', &cpu);
                } else {
                    is_key_press_handled = try pressKey(']', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_BACKSLASH] and is_monitor_ready_for_input) {
                if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
                    is_key_press_handled = try pressKey('|', &cpu);
                } else {
                    is_key_press_handled = try pressKey('\\', &cpu);
                }
            } else if (keyboard_state[sdl.SDL_SCANCODE_RETURN] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(0x0D, &cpu);
            } else if (keyboard_state[sdl.SDL_SCANCODE_ESCAPE] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(0x1B, &cpu);
            }
        }

        try showProcessorState(&cpu, &framebuffer);
        try showTerminalScreen(&framebuffer);
        try showCharSet(&framebuffer);

        _ = sdl.SDL_UpdateTexture(texture, null, &framebuffer, WINDOW_WIDTH * @sizeOf(u32));
        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
        sdl.SDL_RenderPresent(renderer);

        if (cursor_frame_count % 1 == 0 and is_cpu_running) {
            var cycles: usize = 0;
            while (cycles < 1700) : (cycles += 1) {
                try cpu.clock();
            }
        }

        const now = sdl.SDL_GetTicks();
        if (next_frame <= now) {
            sdl.SDL_Delay(0);
        } else {
            sdl.SDL_Delay(next_frame - now);
        }

        next_frame += FRAME_TICKS;
        cursor_frame_count += 1;
        if (cursor_frame_count == 30) {
            cursor_frame_count = 0;
            cursor_state = !cursor_state;
        }
    }
}

fn pressKey(char: u8, cpu: *processor.Cpu) !bool {
    try cpu.bus.write(0xD010, char + 0x80);
    const kbdcr = try cpu.bus.read(0xD011);
    try cpu.bus.write(0xD011, kbdcr | 0x80);
    return true;
}

fn pia_clock(self: *busdevice.BusDevice, last_read_address: ?u16) void {
    // std.debug.print("{X} {X} {X} {X}\n", .{ self.data[0], self.data[1], self.data[2], self.data[3] });

    if (self.data[2] & 0x80 == 0x80) {
        if (self.data[2] != 0x8D) {
            terminal_screen.writeCharacter(self.data[2]);
        } else {
            terminal_screen.newLine();
        }
        self.data[2] = 0;
    }

    if (last_read_address) |address| {
        if (address == 0xD011) {
            self.data[1] &= ~@as(u8, 0x80);
        }
    }
}

var cursor_state = false;
var cursor_frame_count: u8 = 0;

fn showTerminalScreen(framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32) !void {
    var x: u32 = 0;
    var y: u32 = 3;
    var i: usize = 0;
    while (i < 960) : (i += 1) {
        if (cursor_state and i == terminal_screen.cursor_position) {
            try drawCharacterToFramebuffer(&character_set[1], framebuffer, x * 8, y * 8);
        } else {
            try drawCharacterToFramebuffer(&character_set[terminal_screen.buffer[i] % 128], framebuffer, x * 8, y * 8);
        }
        x += 1;
        if (x == 40) {
            x = 0;
            y += 1;
        }
    }
}

fn showProcessorState(cpu: *processor.Cpu, framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32) !void {
    const processor_register_titles = " PC  AC XR YR SP NV-BDIZC  Current instruction:";
    try drawStringToFramebuffer(processor_register_titles, framebuffer, 0, 0);

    var current_instruction_bytes = [_]u8{ cpu.bus.read(cpu.state.pc) catch 0x00, cpu.bus.read(@addWithOverflow(cpu.state.pc, 1)[0]) catch 0x00, cpu.bus.read(@addWithOverflow(cpu.state.pc, 2)[0]) catch 0x00 };
    const current_instruction = try disassembler.disassemble(&current_instruction_bytes);

    var processor_state_buffer = [_]u8{0} ** 60;
    var processor_state_stream = std.io.fixedBufferStream(&processor_state_buffer);
    var writer = processor_state_stream.writer();
    try writer.print("{X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8}  {X:0>2} {X:0>2} {X:0>2} {s}", .{ cpu.state.pc, cpu.state.ac, cpu.state.xr, cpu.state.yr, cpu.state.sp, @as(u8, @bitCast(cpu.state.sr)), current_instruction_bytes[0], current_instruction_bytes[1], current_instruction_bytes[2], current_instruction });
    try drawStringToFramebuffer(&processor_state_buffer, framebuffer, 0, 8);
}

fn showCharSet(framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32) !void {
    var x: u32 = 480;
    var y: u32 = 216;
    var i: u8 = 0;
    var current_char: u8 = 0;
    while (current_char < 128) : (current_char += 1) {
        if (current_char > 0 and current_char % 32 == 0) {
            x += 40;
            y = 216;
        }
        var numbering = [_]u8{0x20} ** 3;
        var numbering_stream = stream(&numbering);
        const writer = numbering_stream.writer();
        try writer.print("{X:0>2}:", .{current_char});
        i = 0;
        while (i < 3) : (i += 1) {
            try drawCharacterToFramebuffer(&character_set[numbering[i]], framebuffer, x + (8 * i), y);
        }
        try drawCharacterToFramebuffer(&character_set[current_char], framebuffer, x + 24, y);
        y += 8;
    }
}

fn explodeU8(input: u8) []u32 {
    var output: [8]u32 = undefined;
    var i: u4 = 0;
    while (i < 8) : (i += 1) {
        if (((input >> @intCast(i)) & 1) == 1) {
            output[i] = 255 + (255 << 8) + (255 << 16) + (255 << 24);
        } else {
            output[i] = 255;
        }
    }
    return &output;
}

fn drawCharacterToFramebuffer(character: *[8]u8, framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32, x: u32, y: u32) ArgumentError!void {
    if ((x + 8 > WINDOW_WIDTH) or (y + 8 > WINDOW_HEIGHT))
        return ArgumentError.OutOfRange;

    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        const exploded = explodeU8(character[i]);
        var char_x: u8 = 0;
        while (char_x < 8) : (char_x += 1) {
            framebuffer[(y + i) * WINDOW_WIDTH + x + char_x] = exploded[char_x];
        }
    }
}

fn drawStringToFramebuffer(string: []const u8, framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32, x: u32, y: u32) ArgumentError!void {
    const length = string.len;
    var i: u32 = 0;
    while (i < length) : (i += 1) {
        drawCharacterToFramebuffer(&character_set[string[i]], framebuffer, x + (8 * i), y) catch |err| return err;
    }
}

const ArgumentError = error{OutOfRange};
