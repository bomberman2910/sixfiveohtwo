const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const processor = @import("./cpu.zig");
const disassembler = @import("./disassembler.zig");
const terminal = @import("./terminal.zig");
const busdevice = @import("./busdevice.zig");
const pixelDisplay = @import("./pixelDisplay.zig");

const stream = std.io.fixedBufferStream;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 960;
const FRAME_TICKS = 17;

const NUMBER_INDEX_START = 48;
const COLON_INDEX = 58;
const SPACE_INDEX = 32;

var character_set: [128][8]u8 = undefined;
var terminal_screen = terminal.TerminalScreen.init();
var pixel_screen = pixelDisplay.PixelScreen.init();

var cursor_frame_count: u8 = 0;

var non_shifted_scancodes = [_]u8{0} ** 512;
var shifted_scancodes = [_]u8{0} ** 512;

pub fn main() !void {
    const character_rom = @embedFile("charmap.rom");
    var character_stream = stream(character_rom);
    var i: u8 = 0;
    while (i < 128) : (i += 1) {
        var character: [8]u8 = undefined;
        _ = try character_stream.read(&character);
        character_set[i] = character;
    }
    @memcpy(pixel_screen.character_set[0..127], character_set[0..127]);
    @memcpy(pixel_screen.character_set[128..255], character_set[0..127]);

    try pixel_screen.switchToTextMode();

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

    const texture = sdl.SDL_CreateTexture(renderer, sdl.SDL_PIXELFORMAT_RGB888, sdl.SDL_TEXTUREACCESS_STATIC, WINDOW_WIDTH, WINDOW_HEIGHT) orelse {
        sdl.SDL_Log("Unable to create texture: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyTexture(texture);

    var next_frame = sdl.SDL_GetTicks() + FRAME_TICKS;
    var quit = false;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var keyboard_state: [512]bool = [_]bool{false} ** 512;
    fillScancodeArrays();

    var cpu = processor.Cpu.init(allocator);
    defer cpu.deinit();

    // base RAM
    try cpu.bus.addDevice(0x0000, 0x0400, null, false);
    // text/lowres page 1 RAM
    try cpu.bus.addDevice(0x0400, 0x0400, move_text_buffer, false);
    // text/lowres page 2 RAM
    try cpu.bus.addDevice(0x0800, 0x0400, null, false);
    // hires page 1
    try cpu.bus.addDevice(0x2000, 0x2000, null, false);
    // hires page 2
    try cpu.bus.addDevice(0x4000, 0x2000, null, false);
    // free RAM
    try cpu.bus.addDevice(0x0C00, 0x1400, null, false);
    // free RAM
    try cpu.bus.addDevice(0x6000, 0x6000, null, false);
    // ROM
    // Apple 2 graphics control registers
    try cpu.bus.addDevice(0xC050, 0x0008, graphics_clock, false);
    // PIA
    //try cpu.bus.addDevice(0xD010, 0x0004, pia_clock, false);

    // Apple 2 ROMs
    try cpu.bus.addDevice(0xD000, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xD000, @embedFile("341011d0.bin"));
    try cpu.bus.addDevice(0xD800, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xD800, @embedFile("341012d8.bin"));
    try cpu.bus.addDevice(0xE000, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xE000, @embedFile("341013e0.bin"));
    try cpu.bus.addDevice(0xE800, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xE800, @embedFile("341014e8.bin"));
    try cpu.bus.addDevice(0xF000, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xF000, @embedFile("341015f0.bin"));
    try cpu.bus.addDevice(0xF800, 0x0800, null, true);
    try cpu.bus.writeToDevice(0xF800, @embedFile("341020f8.bin"));

    // Apple 2 soft switches
    try cpu.bus.addDevice(0xC000, 0x0001, clear_keyboard_strobe, false); // keyboard data register
    try cpu.bus.addDevice(0xC010, 0x0001, null, false); // keyboard data available latch
    try cpu.bus.addDevice(0xC030, 0x0001, null, false); // toggle speaker diaphragm
    try cpu.bus.addDevice(0xC058, 0x0008, null, false); // annunciator inputs
    try cpu.bus.addDevice(0xCFFF, 0x0001, null, false); // slot c8 ROM switch out

    //Apple 2 slot cards
    try cpu.bus.addDevice(0xC100, 0x0100, null, true); // slot 1
    try cpu.bus.addDevice(0xC200, 0x0100, null, true); // slot 2
    try cpu.bus.addDevice(0xC300, 0x0100, null, true); // slot 3
    try cpu.bus.addDevice(0xC400, 0x0100, null, true); // slot 4
    try cpu.bus.addDevice(0xC500, 0x0100, null, true); // slot 5
    try cpu.bus.addDevice(0xC600, 0x0100, null, true); // slot 6
    try cpu.bus.addDevice(0xC700, 0x0100, null, true); // slot 7
    try cpu.bus.addDevice(0xC800, 0x0800, null, true); // extended slot ROM

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

        is_key_press_handled = try handleKeyPress(is_key_press_handled, keyboard_state, &cpu, &is_cpu_running);

        if (pixel_screen.is_in_textmode) {
            try pixel_screen.renderTextToFrameBuffer();
        } else {
            try pixel_screen.renderLowResBufferToFrameBuffer();
        }

        try showProcessorState(&cpu);
        showTerminalScreen();

        var current_cycles_buffer = [_]u8{0} ** 20;
        var current_cycles_stream = std.io.fixedBufferStream(&current_cycles_buffer);
        var writer = current_cycles_stream.writer();
        try writer.print("{d}", .{cpu.total_cycles});
        sdl.SDL_SetWindowTitle(window, &current_cycles_buffer);

        var zoomed_buffer = [_]u24{0} ** (WINDOW_WIDTH * WINDOW_HEIGHT);
        var x: usize = 0;
        var y: usize = 0;
        while (y < WINDOW_HEIGHT) : (y += 2) {
            while (x < WINDOW_WIDTH) : (x += 2) {
                zoomed_buffer[y * WINDOW_WIDTH + x] = pixel_screen.frame_buffer[(y / 2) * (WINDOW_WIDTH / 2) + (x / 2)];
                zoomed_buffer[y * WINDOW_WIDTH + x + 1] = pixel_screen.frame_buffer[(y / 2) * (WINDOW_WIDTH / 2) + (x / 2)];
                zoomed_buffer[(y + 1) * WINDOW_WIDTH + x] = pixel_screen.frame_buffer[(y / 2) * (WINDOW_WIDTH / 2) + (x / 2)];
                zoomed_buffer[(y + 1) * WINDOW_WIDTH + x + 1] = pixel_screen.frame_buffer[(y / 2) * (WINDOW_WIDTH / 2) + (x / 2)];
            }
            x = 0;
        }

        _ = sdl.SDL_UpdateTexture(texture, null, &zoomed_buffer, WINDOW_WIDTH * @sizeOf(u24));
        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
        sdl.SDL_RenderPresent(renderer);

        if (cursor_frame_count % 1 == 0 and is_cpu_running) {
            var cycles: usize = 0;
            while (cycles < 16666) : (cycles += 1) {
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
            terminal_screen.toggleCursor();
        }
    }
}

fn fillScancodeArrays() void {
    var i: usize = 4;
    // letters
    while (i < 30) : (i += 1) {
        non_shifted_scancodes[i] = @as(u8, @intCast(i)) + 61;
    }
    // numbers
    while (i < 39) : (i += 1) {
        non_shifted_scancodes[i] = @as(u8, @intCast(i)) + 19;
    }
    non_shifted_scancodes[sdl.SDL_SCANCODE_0] = '0';
    // special and control characters
    non_shifted_scancodes[sdl.SDL_SCANCODE_RETURN] = 0x0D;
    non_shifted_scancodes[sdl.SDL_SCANCODE_ESCAPE] = 0x1B;
    non_shifted_scancodes[sdl.SDL_SCANCODE_BACKSPACE] = '_';
    non_shifted_scancodes[sdl.SDL_SCANCODE_EQUALS] = '=';
    non_shifted_scancodes[sdl.SDL_SCANCODE_MINUS] = '-';
    non_shifted_scancodes[sdl.SDL_SCANCODE_SLASH] = '/';
    non_shifted_scancodes[sdl.SDL_SCANCODE_COMMA] = ',';
    non_shifted_scancodes[sdl.SDL_SCANCODE_SPACE] = ' ';
    non_shifted_scancodes[sdl.SDL_SCANCODE_PERIOD] = '.';
    non_shifted_scancodes[sdl.SDL_SCANCODE_SEMICOLON] = ';';
    non_shifted_scancodes[sdl.SDL_SCANCODE_APOSTROPHE] = '\'';
    non_shifted_scancodes[sdl.SDL_SCANCODE_LEFTBRACKET] = '[';
    non_shifted_scancodes[sdl.SDL_SCANCODE_RIGHTBRACKET] = ']';
    non_shifted_scancodes[sdl.SDL_SCANCODE_BACKSLASH] = '\\';
    non_shifted_scancodes[sdl.SDL_SCANCODE_DELETE] = 0x7F;
    // arrow keys
    non_shifted_scancodes[sdl.SDL_SCANCODE_LEFT] = 0x08;
    non_shifted_scancodes[sdl.SDL_SCANCODE_UP] = 0x0B;
    non_shifted_scancodes[sdl.SDL_SCANCODE_RIGHT] = 0x15;
    non_shifted_scancodes[sdl.SDL_SCANCODE_DOWN] = 0x0A;

    shifted_scancodes[sdl.SDL_SCANCODE_1] = '!';
    shifted_scancodes[sdl.SDL_SCANCODE_2] = '@';
    shifted_scancodes[sdl.SDL_SCANCODE_3] = '#';
    shifted_scancodes[sdl.SDL_SCANCODE_4] = '$';
    shifted_scancodes[sdl.SDL_SCANCODE_5] = '%';
    shifted_scancodes[sdl.SDL_SCANCODE_6] = '^';
    shifted_scancodes[sdl.SDL_SCANCODE_7] = '&';
    shifted_scancodes[sdl.SDL_SCANCODE_8] = '*';
    shifted_scancodes[sdl.SDL_SCANCODE_9] = '(';
    shifted_scancodes[sdl.SDL_SCANCODE_0] = ')';
    shifted_scancodes[sdl.SDL_SCANCODE_MINUS] = '_';
    shifted_scancodes[sdl.SDL_SCANCODE_EQUALS] = '+';
    shifted_scancodes[sdl.SDL_SCANCODE_LEFTBRACKET] = '{';
    shifted_scancodes[sdl.SDL_SCANCODE_RIGHTBRACKET] = '}';
    shifted_scancodes[sdl.SDL_SCANCODE_SEMICOLON] = ':';
    shifted_scancodes[sdl.SDL_SCANCODE_APOSTROPHE] = '"';
    shifted_scancodes[sdl.SDL_SCANCODE_BACKSLASH] = '|';
    shifted_scancodes[sdl.SDL_SCANCODE_COMMA] = '<';
    shifted_scancodes[sdl.SDL_SCANCODE_PERIOD] = '>';
    shifted_scancodes[sdl.SDL_SCANCODE_SLASH] = '?';
}

fn handleKeyPress(is_key_press_handled: bool, keyboard_state: [512]bool, cpu: *processor.Cpu, is_cpu_running: *bool) !bool {
    if (is_key_press_handled) {
        return true;
    }
    // emulator control
    if (keyboard_state[sdl.SDL_SCANCODE_F5]) {
        try cpu.reset();
        return true;
    } else if (keyboard_state[sdl.SDL_SCANCODE_F10]) {
        if (!is_cpu_running.*)
            try cpu.clock();
        return true;
    } else if (keyboard_state[sdl.SDL_SCANCODE_F11]) {
        is_cpu_running.* = !is_cpu_running.*;
        return true;
        // hex characters
    } else {
        var pressed_key: usize = 0;
        while (!keyboard_state[pressed_key] and pressed_key < 128) : (pressed_key += 1) {}
        if (pressed_key == 128) {
            return false;
        }
        if (keyboard_state[sdl.SDL_SCANCODE_LSHIFT] or keyboard_state[sdl.SDL_SCANCODE_RSHIFT]) {
            if (shifted_scancodes[pressed_key] > 0) {
                return pressKey(shifted_scancodes[pressed_key], cpu);
            }
        } else {
            if (non_shifted_scancodes[pressed_key] > 0) {
                return pressKey(non_shifted_scancodes[pressed_key], cpu);
            }
        }
    }

    return false;
}

fn clear_keyboard_strobe(self: *busdevice.BusDevice, last_read_address: ?u16) !void {
    if (last_read_address == 0xC010) {
        self.data[0] = self.data[0] & 0x7F;
    }
}

fn pressKey(char: u8, cpu: *processor.Cpu) !bool {
    try cpu.bus.write(0xC000, char + 0x80);
    return true;
}

fn pia_clock(self: *busdevice.BusDevice, last_read_address: ?u16) !void {
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

var last_graphics_register_state = [_]u8{0} ** 8;
fn graphics_clock(self: *busdevice.BusDevice, last_read_address: ?u16) !void {
    var changed_registers = [_]bool{false} ** 8;
    var i: u4 = 0;
    while (i < 8) : (i += 1) {
        if (self.data[i] != last_graphics_register_state[i]) {
            changed_registers[i] = true;
            last_graphics_register_state[i] = self.data[i];
        }
    }
    if (last_read_address.? >= 0xC050 and last_read_address.? <= 0xC057) {
        std.debug.print("{X}\n", .{last_read_address.?});
    }
    if (changed_registers[0] or last_read_address == 0xC050) { // switch to graphics mode
        pixel_screen.switchToGraphicsMode();
    } else if (changed_registers[1] or last_read_address == 0xC051) { // switch to text mode
        try pixel_screen.switchToTextMode();
    } else if (changed_registers[2] or last_read_address == 0xC052) { // full screen graphics
        // TODO to be implemented
    } else if (changed_registers[3] or last_read_address == 0xC053) { // mixed screen graphics/text
        // TODO to be implemented
    } else if (changed_registers[4] or last_read_address == 0xC054) { // switch to page 1
        // TODO to be implemented
    } else if (changed_registers[5] or last_read_address == 0xC055) { // switch to page 2
        // TODO to be implemented
    } else if (changed_registers[6] or last_read_address == 0xC056) { // switch to low res graphics
        pixel_screen.is_graphics_high_resolution = false;
    } else if (changed_registers[7] or last_read_address == 0xC057) { // switch to high res graphics
        pixel_screen.is_graphics_high_resolution = true;
    }
}

fn move_text_buffer(self: *busdevice.BusDevice, last_read_address: ?u16) !void {
    _ = last_read_address;
    //if (pixel_screen.is_in_textmode) {
    //    @memcpy(pixel_screen.text_buffer[0..(40 * 24)], terminal_screen.buffer[0..(40 * 24)]);
    //} else if (!pixel_screen.is_in_textmode and !pixel_screen.is_graphics_high_resolution) {
    var i: usize = 0;
    var line_start_address: u16 = 0x0000;
    while (i < 8) : (i += 1) {
        @memcpy(pixel_screen.text_buffer[(i * 40)..(i * 40 + 40)], self.data[(line_start_address + (i * 0x80))..(line_start_address + (i * 0x80) + 40)]);
    }
    line_start_address = 0x0028;
    while (i < 16) : (i += 1) {
        @memcpy(pixel_screen.text_buffer[(i * 40)..(i * 40 + 40)], self.data[(line_start_address + (i % 8 * 0x80))..(line_start_address + (i % 8 * 0x80) + 40)]);
    }
    line_start_address = 0x0050;
    while (i < 24) : (i += 1) {
        @memcpy(pixel_screen.text_buffer[(i * 40)..(i * 40 + 40)], self.data[(line_start_address + (i % 8 * 0x80))..(line_start_address + (i % 8 * 0x80) + 40)]);
    }
    //} else {
    // TODO ignore hi res for now
    //}
}

fn showTerminalScreen() void {
    @memcpy(pixel_screen.text_buffer[0..(40 * 24)], terminal_screen.buffer[0..(40 * 24)]);
}

fn showProcessorState(cpu: *processor.Cpu) !void {
    const processor_register_titles = " PC  AC XR YR SP    SR     Instruction:";
    try drawStringToFramebuffer(processor_register_titles, 0, 0, (255 << 16) + (255 << 8));

    var current_instruction_bytes = [_]u8{ cpu.bus.read(cpu.state.pc) catch 0x00, cpu.bus.read(@addWithOverflow(cpu.state.pc, 1)[0]) catch 0x00, cpu.bus.read(@addWithOverflow(cpu.state.pc, 2)[0]) catch 0x00 };

    var processor_state_buffer = [_]u8{0} ** 40;
    var processor_state_stream = std.io.fixedBufferStream(&processor_state_buffer);
    var writer = processor_state_stream.writer();
    try writer.print("{X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8}  {X:0>2} {X:0>2} {X:0>2}", .{ cpu.state.pc, cpu.state.ac, cpu.state.xr, cpu.state.yr, cpu.state.sp, @as(u8, @bitCast(cpu.state.sr)), current_instruction_bytes[0], current_instruction_bytes[1], current_instruction_bytes[2] });
    try drawStringToFramebuffer(&processor_state_buffer, 0, 16, 255 + (255 << 8) + (255 << 16));

    const current_instruction = try disassembler.disassemble(&current_instruction_bytes);
    var instruction_buffer = [_]u8{0} ** 40;
    var instruction_buffer_stream = std.io.fixedBufferStream(&instruction_buffer);
    writer = instruction_buffer_stream.writer();
    try writer.print("                           {s}", .{current_instruction});
    try drawStringToFramebuffer(&instruction_buffer, 0, 32, 255 << 8);

    var keyboard_state_buffer = [_]u8{0} ** 8;
    var keyboard_state_stream = std.io.fixedBufferStream(&keyboard_state_buffer);
    writer = keyboard_state_stream.writer();
    try writer.print("C000:{X:0>2}", .{cpu.bus.read(0xC000) catch 0xFF});
    try drawStringToFramebuffer(&keyboard_state_buffer, 41 * 8, 0, 255 << 8);
    try keyboard_state_stream.seekTo(0);
    try writer.print("C010:{X:0>2}", .{cpu.bus.read(0xC010) catch 0xFF});
    try drawStringToFramebuffer(&keyboard_state_buffer, 41 * 8, 16, 255 << 8);
}

fn drawStringToFramebuffer(string: []const u8, x: u32, y: u32, foreground: u24) !void {
    const length = string.len;
    var i: u32 = 0;
    while (i < length) : (i += 1) {
        pixel_screen.drawCharacterToFramebuffer8x16(&pixel_screen.character_set[string[i]], x + (8 * i), y, foreground) catch |err| return err;
    }
}
