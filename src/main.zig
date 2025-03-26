const std = @import("std");
const processor = @import("./cpu.zig");
const disassembler = @import("./disassembler.zig");
const terminal = @import("./terminal.zig");
const busdevice = @import("./busdevice.zig");
const raylib = @import("raylib");

const stream = std.io.fixedBufferStream;

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 480;
const FRAME_TICKS: comptime_float = 17 / 1000;

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

    raylib.initWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "sixfiveohtwo");
    defer raylib.closeWindow();
    raylib.setTargetFPS(60);
    raylib.setExitKey(raylib.KeyboardKey.null);

    var framebuffer = [_]u32{255} ** (WINDOW_WIDTH * WINDOW_HEIGHT);
    var next_frame = raylib.getTime() + FRAME_TICKS;
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

    while (!raylib.windowShouldClose()) {
        // TODO the entire input system is fucked
        var pressed_key = @as(usize, @intFromEnum(raylib.KeyboardKey.null));
        var key_index: u16 = 0;
        while (key_index < 512) : (key_index += 1) {
            keyboard_state[pressed_key] = false;
        }
        while (pressed_key != @as(usize, @intFromEnum(raylib.KeyboardKey.null))) {
            keyboard_state[pressed_key] = true;
            pressed_key = @as(usize, @intCast(@intFromEnum(raylib.getKeyPressed())));
        }
        is_key_press_handled = false;

        const is_monitor_ready_for_input = try cpu.bus.read(0xD011) & 0x80 != 0x80;

        if (!is_key_press_handled) {
            // emulator control
            if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.f5))]) {
                try cpu.reset();
                is_key_press_handled = true;
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.f10))]) {
                if (!is_cpu_running)
                    try cpu.clock();
                is_key_press_handled = true;
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.f11))]) {
                is_cpu_running = !is_cpu_running;
                is_key_press_handled = true;
            }
            // hex characters
            else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.zero))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey(')', &cpu);
                } else {
                    is_key_press_handled = try pressKey('0', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.one))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('!', &cpu);
                } else {
                    is_key_press_handled = try pressKey('1', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.two))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('@', &cpu);
                } else {
                    is_key_press_handled = try pressKey('2', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.three))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('#', &cpu);
                } else {
                    is_key_press_handled = try pressKey('3', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.four))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('$', &cpu);
                } else {
                    is_key_press_handled = try pressKey('4', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.five))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('%', &cpu);
                } else {
                    is_key_press_handled = try pressKey('5', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.six))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('^', &cpu);
                } else {
                    is_key_press_handled = try pressKey('6', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.seven))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('&', &cpu);
                } else {
                    is_key_press_handled = try pressKey('7', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.eight))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('*', &cpu);
                } else {
                    is_key_press_handled = try pressKey('8', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.nine))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('(', &cpu);
                } else {
                    is_key_press_handled = try pressKey('9', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.a))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('A', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.b))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('B', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.c))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('C', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.d))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('D', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.e))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('E', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.f))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('F', &cpu);
            }
            // remaining letters
            else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.g))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('G', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.h))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('H', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.i))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('I', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.j))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('J', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.k))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('K', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.l))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('L', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.m))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('M', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.n))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('N', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.o))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('O', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.p))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('P', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.q))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Q', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.r))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('R', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.s))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('S', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.t))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('T', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.u))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('U', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.v))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('V', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.w))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('W', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.x))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('X', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.y))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Y', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.z))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('Z', &cpu);
            }
            // control keys and special characters
            else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.backspace))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey('_', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.equal))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('+', &cpu);
                } else {
                    is_key_press_handled = try pressKey('=', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.minus))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('_', &cpu);
                } else {
                    is_key_press_handled = try pressKey('-', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.slash))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('?', &cpu);
                } else {
                    is_key_press_handled = try pressKey('/', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.comma))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('<', &cpu);
                } else {
                    is_key_press_handled = try pressKey(',', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.space))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(' ', &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.period))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('>', &cpu);
                } else {
                    is_key_press_handled = try pressKey('.', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.semicolon))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey(':', &cpu);
                } else {
                    is_key_press_handled = try pressKey(';', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.apostrophe))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('"', &cpu);
                } else {
                    is_key_press_handled = try pressKey('\'', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_bracket))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('{', &cpu);
                } else {
                    is_key_press_handled = try pressKey('[', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_bracket))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('}', &cpu);
                } else {
                    is_key_press_handled = try pressKey(']', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.backslash))] and is_monitor_ready_for_input) {
                if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.left_shift))] or keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.right_shift))]) {
                    is_key_press_handled = try pressKey('|', &cpu);
                } else {
                    is_key_press_handled = try pressKey('\\', &cpu);
                }
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.enter))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(0x0D, &cpu);
            } else if (keyboard_state[@as(usize, @intFromEnum(raylib.KeyboardKey.escape))] and is_monitor_ready_for_input) {
                is_key_press_handled = try pressKey(0x1B, &cpu);
            }
        }

        try showProcessorState(&cpu, &framebuffer);
        try showTerminalScreen(&framebuffer);
        // try showCharSet(&framebuffer);

        var current_cycles_buffer = [_]u8{0} ** 20;
        var current_cycles_stream = std.io.fixedBufferStream(&current_cycles_buffer);
        var writer = current_cycles_stream.writer();
        try writer.print("{d}", .{cpu.total_cycles});

        raylib.beginDrawing();
        defer raylib.endDrawing();

        const image = raylib.Image{ .data = &framebuffer, .width = WINDOW_WIDTH, .height = WINDOW_HEIGHT, .format = raylib.PixelFormat.uncompressed_r8g8b8a8, .mipmaps = 1 };
        const texture = try raylib.loadTextureFromImage(image);
        defer texture.unload();
        raylib.clearBackground(raylib.Color.black);
        raylib.drawTexture(texture, 0, 0, raylib.Color.white);

        if (cursor_frame_count % 1 == 0 and is_cpu_running) {
            var cycles: usize = 0;
            while (cycles < 16666) : (cycles += 1) {
                try cpu.clock();
            }
        }

        const now = raylib.getTime();
        if (next_frame <= now) {
            raylib.waitTime(0);
        } else {
            raylib.waitTime(next_frame - now);
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
            try drawCharacterToFramebuffer(&character_set[1], framebuffer, x * 8, y * 16);
        } else {
            try drawCharacterToFramebuffer(&character_set[terminal_screen.buffer[i] % 128], framebuffer, x * 8, y * 16);
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
    try drawStringToFramebuffer(&processor_state_buffer, framebuffer, 0, 16);
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
    if ((x + 16 > WINDOW_WIDTH) or (y + 16 > WINDOW_HEIGHT))
        return ArgumentError.OutOfRange;

    var i: u8 = 0;
    while (i < 16) : (i += 2) {
        const exploded = explodeU8(character[i / 2]);
        var char_x: u8 = 0;
        while (char_x < 8) : (char_x += 1) {
            framebuffer[(y + i) * WINDOW_WIDTH + x + char_x] = exploded[char_x];
            framebuffer[(y + i + 1) * WINDOW_WIDTH + x + char_x] = exploded[char_x];
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
