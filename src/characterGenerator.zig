const std = @import("std");
const stream = std.io.fixedBufferStream;

pub const CharacterGenerator = struct {
    raw_character_set: [64][8]u8,
    is_blink_inversed: bool,

    pub fn init() CharacterGenerator {
        var result = CharacterGenerator{ .raw_character_set = [_][8]u8{[_]u8{0} ** 8} ** 64, .is_blink_inversed = false };
        const char_rom_data = @embedFile("charmap.rom");
        var character_stream = stream(char_rom_data);
        try character_stream.seekBy(0x20 * 8);
        var i: u9 = 0;
        while (i < 32) : (i += 1) {
            var character: [8]u8 = undefined;
            _ = try character_stream.read(&character);
            result.raw_character_set[i + 0x20] = character;
        }
        while (i < 64) : (i += 1) {
            var character: [8]u8 = undefined;
            _ = try character_stream.read(&character);
            result.raw_character_set[i - 0x20] = character;
        }
        return result;
    }

    pub fn getCharacter(self: CharacterGenerator, character_code: u8) [8]u8 {
        var character = self.raw_character_set[character_code % 64];
        if (character_code < 64 or (character_code >= 64 and character_code < 128 and self.is_blink_inversed)) {
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                character[i] = ~character[i];
            }
        }
        return character;
    }
};

test "CharacterGenerator_init" {
    const generator = CharacterGenerator.init();
    try std.testing.expectEqual(0x08, generator.raw_character_set[33][4]);
    try std.testing.expectEqual(0x00, generator.raw_character_set[33][5]);
    try std.testing.expectEqual(0x22, generator.raw_character_set[1][2]);
    try std.testing.expectEqual(0x3E, generator.raw_character_set[1][4]);
}

test "CharacterGenerator_getCharacter" {
    var generator = CharacterGenerator.init();
    const inverted_a = generator.getCharacter(1);
    const flashing_a_noninverted = generator.getCharacter(65);
    generator.is_blink_inversed = true;
    const flashing_a_inverted = generator.getCharacter(65);
    const noninverted_a = generator.getCharacter(129);
    const noninverted_a_from_mirror = generator.getCharacter(193);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x14, 0x22, 0x22, 0x3E, 0x22, 0x22, 0x00 }, &noninverted_a);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x14, 0x22, 0x22, 0x3E, 0x22, 0x22, 0x00 }, &noninverted_a_from_mirror);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x08, 0x14, 0x22, 0x22, 0x3E, 0x22, 0x22, 0x00 }, &flashing_a_noninverted);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xF7, 0xEB, 0xDD, 0xDD, 0xC1, 0xDD, 0xDD, 0xFF }, &inverted_a);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xF7, 0xEB, 0xDD, 0xDD, 0xC1, 0xDD, 0xDD, 0xFF }, &flashing_a_inverted);
}
