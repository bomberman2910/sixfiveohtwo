const std = @import("std");

const EMPTY_TEXT_BUFFER: [40 * 24]u8 = [_]u8{0x20} ** (40 * 24);
const FRAME_BUFFER_WIDTH = 640;
const FRAME_BUFFER_HEIGHT = 480;

pub const PixelScreen = struct {
    frame_buffer: [FRAME_BUFFER_WIDTH * FRAME_BUFFER_HEIGHT]u24,
    is_in_textmode: bool,
    text_buffer: [40 * 24]u8,
    character_set: [256][8]u8,
    is_graphics_high_resolution: bool,

    pub fn init() PixelScreen {
        return PixelScreen{ .frame_buffer = [_]u24{std.math.maxInt(u24)} ** (FRAME_BUFFER_WIDTH * FRAME_BUFFER_HEIGHT), .is_in_textmode = false, .text_buffer = [_]u8{0x20} ** (40 * 24), .character_set = [_][8]u8{[_]u8{0} ** 8} ** 256, .is_graphics_high_resolution = false };
    }

    pub fn switchToTextMode(self: *PixelScreen) !void {
        std.debug.print("switching to text mode\n", .{});
        self.is_in_textmode = true;
        @memcpy(self.text_buffer[0..(40 * 24)], EMPTY_TEXT_BUFFER[0..(40 * 24)]);
        try self.renderTextToFrameBuffer();
    }

    pub fn switchToGraphicsMode(self: *PixelScreen) void {
        std.debug.print("switching to graphics mode\n", .{});
        self.is_in_textmode = false;
        if (!self.is_graphics_high_resolution) {
            @memcpy(self.text_buffer[0..(40 * 24)], EMPTY_TEXT_BUFFER[0..(40 * 24)]);
        }
    }

    pub fn setPixel(self: *PixelScreen, x: u32, y: u32, color: u4) ArgumentError!void {
        if (self.is_in_textmode) {
            return;
        }
        if (!self.is_graphics_high_resolution) {
            if (x >= 40 or y >= 48) {
                return ArgumentError.OutOfRange;
            }
            const cell_content = self.text_buffer[(y / 2) * 40 + x];
            const is_pixel_in_upper_half = (y % 2) == 0;
            if (is_pixel_in_upper_half) {
                const bottom_half = cell_content & 0x0F;
                self.text_buffer[(y / 2) * 40 + x] = (color << 4) | bottom_half;
            } else {
                const upper_half = cell_content & 0xF0;
                self.text_buffer[(y / 2) * 40 + x] = upper_half | color;
            }
            try self.renderLowResBufferToFrameBuffer();
        }
    }

    pub fn renderLowResBufferToFrameBuffer(self: *PixelScreen) !void {
        if (self.is_in_textmode) {
            return;
        }
        var square = [_]u8{ 255, 255, 255, 255, 0, 0, 0, 0 };

        var x: u32 = 0;
        var y: u32 = 3; // leave three rows of text free at the top (24 pixels)
        var i: usize = 0;
        while (i < (40 * 24)) : (i += 1) {
            try self.drawCharacterToFramebuffer16x16WithBackground(&square, x * 16, y * 16, colorCodeToRgb(@truncate(self.text_buffer[(y - 3) * 40 + x] >> 4)), colorCodeToRgb(@truncate(self.text_buffer[(y - 3) * 40 + x] & 0xF)));
            x += 1;
            if (x == 40) {
                x = 0;
                y += 1;
            }
        }
    }

    pub fn renderTextToFrameBuffer(self: *PixelScreen) !void {
        if (!self.is_in_textmode) {
            return;
        }
        var x: u32 = 0;
        var y: u32 = 3; // leave three rows of text free at the top (24 pixels)
        var i: usize = 0;
        while (i < (40 * 24)) : (i += 1) {
            try self.drawCharacterToFramebuffer16x16(&self.character_set[self.text_buffer[i]], x * 16, y * 16, 255 + (255 << 8) + (255 << 16));
            x += 1;
            if (x == 40) {
                x = 0;
                y += 1;
            }
        }
    }

    pub fn drawCharacterToFramebuffer16x16(self: *PixelScreen, character: *[8]u8, x: u32, y: u32, foreground: u24) ArgumentError!void {
        if ((x + 16 > FRAME_BUFFER_WIDTH) or (y + 16 > FRAME_BUFFER_HEIGHT))
            return ArgumentError.OutOfRange;

        var i: u8 = 0;
        while (i < 16) : (i += 2) {
            const exploded = explodeU8(character[(i / 2)], 0, foreground);
            var char_x: u8 = 0;
            while (char_x < 8) : (char_x += 1) {
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + 1 + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i + 1) * FRAME_BUFFER_WIDTH + x + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i + 1) * FRAME_BUFFER_WIDTH + x + 1 + (char_x * 2)] = exploded[char_x];
            }
        }
    }

    pub fn drawCharacterToFramebuffer16x16WithBackground(self: *PixelScreen, character: *[8]u8, x: u32, y: u32, foreground: u24, background: u24) ArgumentError!void {
        if ((x + 16 > FRAME_BUFFER_WIDTH) or (y + 16 > FRAME_BUFFER_HEIGHT))
            return ArgumentError.OutOfRange;

        var i: u8 = 0;
        while (i < 16) : (i += 2) {
            const exploded = explodeU8(character[(i / 2)], background, foreground);
            var char_x: u8 = 0;
            while (char_x < 8) : (char_x += 1) {
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + 1 + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i + 1) * FRAME_BUFFER_WIDTH + x + (char_x * 2)] = exploded[char_x];
                self.frame_buffer[(y + i + 1) * FRAME_BUFFER_WIDTH + x + 1 + (char_x * 2)] = exploded[char_x];
            }
        }
    }

    pub fn drawCharacterToFramebuffer8x16(self: *PixelScreen, character: *[8]u8, x: u32, y: u32, foreground: u24) ArgumentError!void {
        if ((x + 8 > FRAME_BUFFER_WIDTH) or (y + 16 > FRAME_BUFFER_HEIGHT))
            return ArgumentError.OutOfRange;

        var i: u8 = 0;
        while (i < 16) : (i += 2) {
            const exploded = explodeU8(character[(i / 2)], 0, foreground);
            var char_x: u8 = 0;
            while (char_x < 8) : (char_x += 1) {
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + char_x] = exploded[char_x];
                self.frame_buffer[(y + i + 1) * FRAME_BUFFER_WIDTH + x + char_x] = exploded[char_x];
            }
        }
    }

    pub fn drawCharacterToFramebuffer8x8(self: *PixelScreen, character: *[8]u8, x: u32, y: u32, foreground: u24) ArgumentError!void {
        if ((x + 8 > FRAME_BUFFER_WIDTH) or (y + 8 > FRAME_BUFFER_HEIGHT))
            return ArgumentError.OutOfRange;

        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            const exploded = explodeU8(character[i], 0, foreground);
            var char_x: u8 = 0;
            while (char_x < 8) : (char_x += 1) {
                self.frame_buffer[(y + i) * FRAME_BUFFER_WIDTH + x + char_x] = exploded[char_x];
            }
        }
    }

    fn explodeU8(input: u8, background: u24, foreground: u24) []u24 {
        var output: [8]u24 = undefined;
        var i: u4 = 0;
        while (i < 8) : (i += 1) {
            if (((input >> @intCast(i)) & 1) == 1) {
                output[i] = foreground;
            } else {
                output[i] = background;
            }
        }
        return &output;
    }

    fn colorCodeToRgb(code: u4) u24 {
        return switch (code) {
            0 => 0, // black
            1 => 0xCC0033, // magenta
            2 => 0x000099, // dark blue
            3 => 0xCC33CC, // purple
            4 => 0x006633, // dark green
            5 => 0x666666, // dark grey
            6 => 0x3333FF, // medium blue
            7 => 0x6699FF, // light blue
            8 => 0x996600, // brown
            9 => 0xFF6600, // orange
            10 => 0x999999, // light grey
            11 => 0xFF9999, // pink
            12 => 0x00CC00, // light green
            13 => 0xFFFF00, // yellow
            14 => 0x33FF99, // aqua
            15 => 0xFFFFFF, // white
        };
    }

    const ArgumentError = error{OutOfRange};
};
