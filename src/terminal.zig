pub const TerminalScreen = struct {
    buffer: [960]u8,
    cursor_position: u10,

    pub fn init() TerminalScreen {
        return TerminalScreen{ .buffer = [_]u8{0x20} ** 960, .cursor_position = 0 };
    }

    pub fn writeCharacter(self: *TerminalScreen, character: u8) void {
        self.buffer[self.cursor_position] = character;
        self.cursor_position += 1;
        if (self.cursor_position == 960) {
            @memcpy(&self.buffer, self.buffer[40..960] ++ ([_]u8{0x20} ** 40));
            self.cursor_position -= 40;
        }
    }

    pub fn newLine(self: *TerminalScreen) void {
        const position_in_line = self.cursor_position % 40;
        var missing_spaces = @as(u10, 40) - position_in_line;
        while (missing_spaces > 0) : (missing_spaces -= 1) {
            self.writeCharacter(0x20);
        }
    }
};

const testing = @import("std").testing;

test "terminalScreenWriteTest" {
    var screen = TerminalScreen.init();
    screen.writeCharacter(0x40);
    screen.writeCharacter(0x41);
    screen.writeCharacter(0x42);
    screen.writeCharacter(0x43);

    try testing.expectEqualSlices(u8, &[_]u8{ 0x40, 0x41, 0x42, 0x43, 0x20 }, screen.buffer[0..5]);
}

test "terminalScreenScrollTest" {
    var screen = TerminalScreen.init();
    screen.buffer[0] = 0x40;
    screen.buffer[40] = 0x41;
    screen.cursor_position = 959;
    screen.writeCharacter(0x43);

    try testing.expectEqual(0x41, screen.buffer[0]);
    try testing.expectEqual(0x43, screen.buffer[919]);
    try testing.expectEqual(920, screen.cursor_position);
}
