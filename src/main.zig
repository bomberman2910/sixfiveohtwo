const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const processor = @import("./cpu.zig");
const stream = std.io.fixedBufferStream;

const WINDOW_WIDTH = 640;
const WINDOW_HEIGHT = 480;
const FRAME_TICKS = 17;

const NUMBER_INDEX_START = 48;
const COLON_INDEX = 58;
const SPACE_INDEX = 32;

var character_set: [128][8]u8 = undefined;

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

    const screen = sdl.SDL_CreateWindow("", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl.SDL_WINDOW_OPENGL) orelse
        {
        sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyWindow(screen);

    const renderer = sdl.SDL_CreateRenderer(screen, -1, 0) orelse {
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

    var cpu = processor.Cpu.init(allocator);
    defer cpu.deinit();

    while (!quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        var x: u32 = 16;
        var y: u32 = 16;
        var current_char: u8 = 0;
        while (current_char < 128) : (current_char += 1) {
            if (current_char % 32 == 0) {
                x += 48;
                y = 16;
            }
            const numbering = try std.fmt.allocPrint(allocator, "{: >3}:", .{current_char});
            defer allocator.free(numbering);
            i = 0;
            while (i < 4) : (i += 1) {
                try drawCharacterToFramebuffer(&character_set[numbering[i]], &framebuffer, x + (8 * i), y);
            }
            try drawCharacterToFramebuffer(&character_set[current_char], &framebuffer, x + 32, y);
            y += 8;
        }

        var helloWorld = [_]u8{ 'H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd', '!' };
        try drawStringToFramebuffer(&helloWorld, &framebuffer, 0, 0);

        _ = sdl.SDL_UpdateTexture(texture, null, &framebuffer, WINDOW_WIDTH * @sizeOf(u32));
        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);
        sdl.SDL_RenderPresent(renderer);

        const now = sdl.SDL_GetTicks();
        if (next_frame <= now) {
            sdl.SDL_Delay(0);
        } else {
            sdl.SDL_Delay(next_frame - now);
        }
        next_frame += FRAME_TICKS;
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

fn drawStringToFramebuffer(string: []u8, framebuffer: *[WINDOW_WIDTH * WINDOW_HEIGHT]u32, x: u32, y: u32) ArgumentError!void {
    const length = string.len;
    var i: u32 = 0;
    while (i < length) : (i += 1) {
        drawCharacterToFramebuffer(&character_set[string[i]], framebuffer, x + (8 * i), y) catch |err| return err;
    }
}

const ArgumentError = error{OutOfRange};
