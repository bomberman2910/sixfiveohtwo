const std = @import("std");

const EMPTY_TEXT_BUFFER: [40 * 24]u8 = [_]u8{0x20} ** (40 * 24);
const FRAME_BUFFER_WIDTH = 640;
const FRAME_BUFFER_HEIGHT = 480;

pub const PixelScreen = struct {
    frame_buffer: [FRAME_BUFFER_WIDTH * FRAME_BUFFER_HEIGHT]u24,
    is_in_textmode: bool,
    text_buffer: [40 * 24]u8,
    character_set: [256][8]u8,

    pub fn init() PixelScreen {
        return PixelScreen{ .frame_buffer = [_]u24{std.math.maxInt(u24)} ** (FRAME_BUFFER_WIDTH * FRAME_BUFFER_HEIGHT), .is_in_textmode = false, .text_buffer = [_]u8{0x20} ** (40 * 24), .character_set = [_][8]u8{[_]u8{0} ** 8} ** 256 };
    }

    pub fn switchToTextMode(self: *PixelScreen) !void {
        self.is_in_textmode = true;
        @memcpy(self.text_buffer[0..(40 * 24)], EMPTY_TEXT_BUFFER[0..(40 * 24)]);
        try self.renderTextToFrameBuffer();
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

    const ArgumentError = error{OutOfRange};
};
