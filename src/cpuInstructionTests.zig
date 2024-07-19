const std = @import("std");
const processor = @import("cpu.zig");

const State = processor.State;

const Tuple = struct { u16, u8 };
const TestCaseState = struct { cpu: State, memory: []const Tuple = &[0]Tuple{} };
const TestCase = struct { instruction: [3]u8, before: TestCaseState, after: TestCaseState };

const testing_allocator = std.testing.allocator;

fn testCaseSet(test_cases: []const TestCase) !bool {
    var cpu = processor.Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0x0000, 0x10000, null, false);

    var all_tests_successful = true;
    const FailedTestInformation = struct { expected_result: TestCase, actual_state: State, actual_memory: []const Tuple };
    var failed_tests = std.ArrayList(FailedTestInformation).init(testing_allocator);
    defer failed_tests.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(testing_allocator);
    defer {
        _ = arena_allocator.reset(std.heap.ArenaAllocator.ResetMode.free_all);
        arena_allocator.deinit();
    }

    for (test_cases) |test_case| {
        // clear memory for test
        @memset(cpu.bus.devices.items[0].data, 0);

        // set cpu state and memory for test
        cpu.state = test_case.before.cpu;
        var index: u16 = 0x0200;
        while (index < 0x203) : (index = @addWithOverflow(index, 1)[0]) {
            try cpu.bus.write(index, test_case.instruction[index - 0x0200]);
        }
        for (test_case.before.memory) |cell| {
            try cpu.bus.write(cell[0], cell[1]);
        }

        // clock the cpu to execute the instruction
        try cpu.clock();

        // validate cpu state after execution
        const actual_sr: u8 = @bitCast(cpu.state.sr);
        const expected_sr: u8 = @bitCast(test_case.after.cpu.sr);

        const is_memory_after_correct = mem_check: {
            for (test_case.after.memory) |cell| {
                const value = try cpu.bus.read(cell[0]);
                if (cell[1] != value) {
                    break :mem_check false;
                }
            }
            break :mem_check true;
        };

        if (test_case.after.cpu.ac != cpu.state.ac or test_case.after.cpu.pc != cpu.state.pc or test_case.after.cpu.sp != cpu.state.sp or test_case.after.cpu.xr != cpu.state.xr or test_case.after.cpu.yr != cpu.state.yr or expected_sr != actual_sr or !is_memory_after_correct) {
            const actual_memory_slice = get_failed_mem: {
                var actual_memory = std.ArrayList(Tuple).init(arena_allocator.allocator());
                for (test_case.after.memory) |cell| {
                    try actual_memory.append(.{ cell[0], try cpu.bus.read(cell[0]) });
                }
                break :get_failed_mem try actual_memory.toOwnedSlice();
            };
            try failed_tests.append(.{ .expected_result = test_case, .actual_state = cpu.state, .actual_memory = actual_memory_slice });
            all_tests_successful = false;
        }
    }

    if (!all_tests_successful) {
        std.debug.print("\n", .{});
        for (failed_tests.items) |failed_test| {
            std.debug.print(
                \\----------------------------------------------------------
                \\failed test for instruction {X} {X} {X}
                \\          PC  AC XR YR SP NV-BDIZC
                \\initial  {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\actual   {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\expected {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\
                \\
            , .{
                failed_test.expected_result.instruction[0],
                failed_test.expected_result.instruction[1],
                failed_test.expected_result.instruction[2],
                failed_test.expected_result.before.cpu.pc,
                failed_test.expected_result.before.cpu.ac,
                failed_test.expected_result.before.cpu.xr,
                failed_test.expected_result.before.cpu.yr,
                failed_test.expected_result.before.cpu.sp,
                @as(u8, @bitCast(failed_test.expected_result.before.cpu.sr)),
                initial_memory: {
                    if (failed_test.expected_result.before.memory.len == 0)
                        break :initial_memory "";
                    var buffer = [_]u8{0} ** 100;
                    var stream = std.io.fixedBufferStream(&buffer);
                    var writer = stream.writer();
                    try writer.print("{{ ", .{});
                    var i: usize = 0;
                    const last_memory_cell_index = failed_test.expected_result.before.memory.len - 1;
                    while (i < last_memory_cell_index) : (i += 1) {
                        try writer.print("[ {X:0>4}: {X:0>2} ], ", failed_test.expected_result.before.memory[i]);
                    }
                    try writer.print("[ {X:0>4}: {X:0>2} ] }}", failed_test.expected_result.before.memory[last_memory_cell_index]);
                    break :initial_memory std.mem.trimRight(u8, &buffer, "\x00");
                },
                failed_test.actual_state.pc,
                failed_test.actual_state.ac,
                failed_test.actual_state.xr,
                failed_test.actual_state.yr,
                failed_test.actual_state.sp,
                @as(u8, @bitCast(failed_test.actual_state.sr)),
                actual_memory: {
                    if (failed_test.actual_memory.len == 0)
                        break :actual_memory "";
                    var buffer = [_]u8{0} ** 100;
                    var stream = std.io.fixedBufferStream(&buffer);
                    var writer = stream.writer();
                    try writer.print("{{ ", .{});
                    var i: usize = 0;
                    const last_memory_cell_index = failed_test.actual_memory.len - 1;
                    while (i < last_memory_cell_index) : (i += 1) {
                        try writer.print("[ {X:0>4}: {X:0>2} ], ", failed_test.actual_memory[i]);
                    }
                    try writer.print("[ {X:0>4}: {X:0>2} ] }}", failed_test.actual_memory[last_memory_cell_index]);
                    break :actual_memory std.mem.trimRight(u8, &buffer, "\x00");
                },
                failed_test.expected_result.after.cpu.pc,
                failed_test.expected_result.after.cpu.ac,
                failed_test.expected_result.after.cpu.xr,
                failed_test.expected_result.after.cpu.yr,
                failed_test.expected_result.after.cpu.sp,
                @as(u8, @bitCast(failed_test.expected_result.after.cpu.sr)),
                expected_memory: {
                    if (failed_test.expected_result.after.memory.len == 0)
                        break :expected_memory "";
                    var buffer = [_]u8{0} ** 100;
                    var stream = std.io.fixedBufferStream(&buffer);
                    var writer = stream.writer();
                    try writer.print("{{ ", .{});
                    var i: usize = 0;
                    const last_memory_cell_index = failed_test.expected_result.after.memory.len - 1;
                    while (i < last_memory_cell_index) : (i += 1) {
                        try writer.print("[ {X:0>4}: {X:0>2} ], ", failed_test.expected_result.after.memory[i]);
                    }
                    try writer.print("[ {X:0>4}: {X:0>2} ] }}", failed_test.expected_result.after.memory[last_memory_cell_index]);
                    break :expected_memory std.mem.trimRight(u8, &buffer, "\x00");
                },
            });
        }
    }

    return all_tests_successful;
}

test "transferInstructions" {
    const test_cases = [_]TestCase{
        .{
            .instruction = .{ 0x81, 0x24, 0x00 }, // STA ($24, X)
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x33, .ac = 0x45 }, .memory = &[_]Tuple{ .{ 0x0057, 0x48 }, .{ 0x0058, 0x80 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x33, .ac = 0x45 }, .memory = &[_]Tuple{ .{ 0x0057, 0x48 }, .{ 0x0058, 0x80 }, .{ 0x8048, 0x45 } } },
        },
        .{
            .instruction = .{ 0x84, 0x87, 0x00 }, // STY $87
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0xA8 } },
            .after = .{ .cpu = .{ .pc = 0x0202, .yr = 0xA8 }, .memory = &[_]Tuple{.{ 0x0087, 0xA8 }} },
        },
        .{
            .instruction = .{ 0x85, 0xF1, 0x00 }, // STA $F1
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x2D } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x2D }, .memory = &[_]Tuple{.{ 0x00F1, 0x2D }} },
        },
        .{
            .instruction = .{ 0x86, 0x02, 0x00 }, // STX $02
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0xF3 } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0xF3 }, .memory = &[_]Tuple{.{ 0x0002, 0xF3 }} },
        },
        .{
            .instruction = .{ 0x8A, 0x00, 0x00 }, // TXA
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x4F } },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0x4F, .xr = 0x4F } },
        },
        .{
            .instruction = .{ 0x8C, 0x32, 0xA8 }, // STY $A832
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0xFC } },
            .after = .{ .cpu = .{ .pc = 0x0203, .yr = 0xFC }, .memory = &[_]Tuple{.{ 0xA832, 0xFC }} },
        },
        .{
            .instruction = .{ 0x8D, 0xDD, 0xF3 }, // STA $F3DD
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x12 } },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x12 }, .memory = &[_]Tuple{.{ 0xF3DD, 0x12 }} },
        },
        .{
            .instruction = .{ 0x8E, 0xB7, 0x32 }, // STX $32B7
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0xF7 } },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0xF7 }, .memory = &[_]Tuple{.{ 0x32B7, 0xF7 }} },
        },
        .{
            .instruction = .{ 0x91, 0x44, 0x00 }, // STA ($44), Y
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x20, .yr = 0x09 }, .memory = &[_]Tuple{ .{ 0x0044, 0x4A }, .{ 0x0045, 0xF0 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x20, .yr = 0x09 }, .memory = &[_]Tuple{ .{ 0x0044, 0x4A }, .{ 0x0045, 0xF0 }, .{ 0xF053, 0x20 } } },
        },
        .{
            .instruction = .{ 0x94, 0xB5, 0x00 }, // STY $B5, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x01, .yr = 0xFF } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x01, .yr = 0xFF }, .memory = &[_]Tuple{.{ 0x00B6, 0xFF }} },
        },
        .{
            .instruction = .{ 0x95, 0x1C, 0x00 }, // STA $1C, X
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0xFD, .xr = 0x23 } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0xFD, .xr = 0x23 }, .memory = &[_]Tuple{.{ 0x003F, 0xFD }} },
        },
        .{
            .instruction = .{ 0x96, 0x00, 0x00 }, // STX $00, Y
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0xDA, .yr = 0x50 } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0xDA, .yr = 0x50 }, .memory = &[_]Tuple{.{ 0x0050, 0xDA }} },
        },
        .{
            .instruction = .{ 0x98, 0x00, 0x00 }, // TYA
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0xEA } },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0xEA, .yr = 0xEA, .sr = .{ .negative = true } } },
        },
        .{
            .instruction = .{ 0x99, 0x12, 0x4F }, // STA $4F12, Y
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0xBE, .yr = 0x1A } },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0xBE, .yr = 0x1A }, .memory = &[_]Tuple{.{ 0x4F2C, 0xBE }} },
        },
        .{
            .instruction = .{ 0x9A, 0x00, 0x00 }, // TXS
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0xAA } },
            .after = .{ .cpu = .{ .pc = 0x0201, .xr = 0xAA, .sp = 0xAA } },
        },
        .{
            .instruction = .{ 0x9D, 0x3F, 0xAD }, // STA 0xAD3F, X
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x1F, .xr = 0x5D } },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x1F, .xr = 0x5D }, .memory = &[_]Tuple{.{ 0xAD9C, 0x1F }} },
        },
        .{
            .instruction = .{ 0xA0, 0x3A, 0x00 }, // LDY #$3A
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0x00, .sr = .{ .zero = true } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .yr = 0x3A } },
        },
        .{
            .instruction = .{ 0xA1, 0xB2, 0x00 }, // LDA ($B2, X)
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x02, .sr = .{ .negative = true } }, .memory = &[_]Tuple{ .{ 0x00B4, 0xA5 }, .{ 0x00B5, 0xC3 }, .{ 0xC3A5, 0x3E } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x3E, .xr = 0x02 }, .memory = &[_]Tuple{ .{ 0x00B4, 0xA5 }, .{ 0x00B5, 0xC3 }, .{ 0xC3A5, 0x3E } } },
        },
        .{
            .instruction = .{ 0xA2, 0xE2, 0x00 }, // LDX #$E2
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .zero = true } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0xE2, .sr = .{ .negative = true } } },
        },
        .{
            .instruction = .{ 0xA4, 0x09, 0x00 }, // LDY $09
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .negative = true } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .sr = .{ .zero = true } } },
        },
        .{
            .instruction = .{ 0xA5, 0x75, 0x00 }, // LDA $75
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x0075, 0x34 }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x34 }, .memory = &[_]Tuple{.{ 0x0075, 0x34 }} },
        },
        .{
            .instruction = .{ 0xA6, 0xF3, 0x00 }, // LDX $F3
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .zero = true } }, .memory = &[_]Tuple{.{ 0x00F3, 0xC2 }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0xC2, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x00F3, 0xC2 }} },
        },
        .{
            .instruction = .{ 0xA8, 0x00, 0x00 }, // TAY
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0xD2 } },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0xD2, .yr = 0xD2, .sr = .{ .negative = true } } },
        },
        .{
            .instruction = .{ 0xA9, 0x7D, 0x00 }, // LDA #$7D
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .zero = true } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x7D } },
        },
        .{
            .instruction = .{ 0xAA, 0x00, 0x00 }, // TAX
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x2F } },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0x2F, .xr = 0x2F } },
        },
        .{
            .instruction = .{ 0xAC, 0xAE, 0x86 }, // LDY $86AE
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x86AE, 0xFF }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .yr = 0xFF, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x86AE, 0xFF }} },
        },
        .{
            .instruction = .{ 0xAD, 0x31, 0x6D }, // LDA $6D31
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x6D31, 0x29 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x29 }, .memory = &[_]Tuple{.{ 0x6D31, 0x29 }} },
        },
        .{
            .instruction = .{ 0xAE, 0xE7, 0x23 }, // LDX $23E7
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x23E7, 0xC9 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0xC9, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x23E7, 0xC9 }} },
        },
        .{
            .instruction = .{ 0xB1, 0x16, 0x00 }, // LDA ($16), Y
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0x12 }, .memory = &[_]Tuple{ .{ 0x0016, 0x3F }, .{ 0x0017, 0x5C }, .{ 0x5C51, 0x20 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x20, .yr = 0x12 }, .memory = &[_]Tuple{ .{ 0x0016, 0x3F }, .{ 0x0017, 0x5C }, .{ 0x5C51, 0x20 } } },
        },
        .{
            .instruction = .{ 0xB4, 0x38, 0x00 }, // LDY $38, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x4F } },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x4F, .sr = .{ .zero = true } } },
        },
        .{
            .instruction = .{ 0xB5, 0x9A, 0x00 }, // LDA $9A, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x03 }, .memory = &[_]Tuple{.{ 0x009D, 0xDF }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0xDF, .xr = 0x03, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x009D, 0xDF }} },
        },
        .{
            .instruction = .{ 0xB6, 0xBE, 0x00 }, // LDX $BE, Y
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0x24 }, .memory = &[_]Tuple{.{ 0x00E2, 0x1B }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x1B, .yr = 0x24 }, .memory = &[_]Tuple{.{ 0x00E2, 0x1B }} },
        },
        .{
            .instruction = .{ 0xB9, 0x3A, 0xC2 }, // LDA $C23A, Y
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0xA0 }, .memory = &[_]Tuple{.{ 0xC2DA, 0xD1 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0xD1, .yr = 0xA0, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0xC2DA, 0xD1 }} },
        },
        .{
            .instruction = .{ 0xBA, 0x00, 0x00 }, // TSX
            .before = .{ .cpu = .{ .pc = 0x0200, .sp = 0xFA } },
            .after = .{ .cpu = .{ .pc = 0x0201, .sp = 0xFA, .xr = 0xFA, .sr = .{ .negative = true } } },
        },
        .{
            .instruction = .{ 0xBC, 0x31, 0x8F }, // LDY $8F31, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x14 }, .memory = &[_]Tuple{.{ 0x8F45, 0x11 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0x14, .yr = 0x11 }, .memory = &[_]Tuple{.{ 0x8F45, 0x11 }} },
        },
        .{
            .instruction = .{ 0xBD, 0xD3, 0xF1 }, // LDA $F1D3, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x05 }, .memory = &[_]Tuple{.{ 0xF1D8, 0x6F }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x6F, .xr = 0x05 }, .memory = &[_]Tuple{.{ 0xF1D8, 0x6F }} },
        },
        .{
            .instruction = .{ 0xBE, 0x52, 0xA1 }, // LDX $A152, Y
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0x41 }, .memory = &[_]Tuple{.{ 0xA193, 0x22 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0x22, .yr = 0x41 }, .memory = &[_]Tuple{.{ 0xA193, 0x22 }} },
        },
    };
    const success = try testCaseSet(&test_cases);
    try std.testing.expect(success);
}

test "stackInstructions" {
    const test_cases = [_]TestCase{
        .{
            .instruction = .{ 0x08, 0x00, 0x00 }, // PHP
            .before = .{ .cpu = .{ .pc = 0x0200, .sr = .{ .zero = true, .carry = true, .decimal = true } } },
            .after = .{ .cpu = .{ .pc = 0x0201, .sp = 0xFE, .sr = .{ .zero = true, .carry = true, .decimal = true } }, .memory = &[_]Tuple{.{ 0x01FF, 0x3B }} },
        },
        .{
            .instruction = .{ 0x28, 0x00, 0x00 }, // PLP
            .before = .{ .cpu = .{ .pc = 0x0200, .sp = 0xFE }, .memory = &[_]Tuple{.{ 0x01FF, 0x39 }} },
            .after = .{ .cpu = .{ .pc = 0x0201, .sr = .{ .decimal = true, .carry = true } } },
        },
        .{
            .instruction = .{ 0x48, 0x00, 0x00 }, // PHA
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0xDA } },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0xDA, .sp = 0xFE }, .memory = &[_]Tuple{.{ 0x01FF, 0xDA }} },
        },
        .{
            .instruction = .{ 0x68, 0x00, 0x00 }, // PLA
            .before = .{ .cpu = .{ .pc = 0x0200, .sp = 0xFE }, .memory = &[_]Tuple{.{ 0x01FF, 0xD1 }} },
            .after = .{ .cpu = .{ .pc = 0x0201, .ac = 0xD1, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x01FF, 0xD1 }} },
        },
    };
    const success = try testCaseSet(&test_cases);
    try std.testing.expect(success);
}

test "decrementAndIncrementInstructions" {
    const test_cases = [_]TestCase{
        .{
            .instruction = .{ 0x88, 0x00, 0x00 }, // DEY
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0x34 } },
            .after = .{ .cpu = .{ .pc = 0x0201, .yr = 0x33 } },
        },
        .{
            .instruction = .{ 0xC6, 0x4D, 0x00 }, // DEC $4D
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x004D, 0xD3 }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x004D, 0xD2 }} },
        },
        .{
            .instruction = .{ 0xC8, 0x00, 0x00 }, // INY
            .before = .{ .cpu = .{ .pc = 0x0200, .yr = 0xFF } },
            .after = .{ .cpu = .{ .pc = 0x0201, .yr = 0x00, .sr = .{ .zero = true } } },
        },
        .{
            .instruction = .{ 0xCA, 0x00, 0x00 }, // DEX
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x00 } },
            .after = .{ .cpu = .{ .pc = 0x0201, .xr = 0xFF, .sr = .{ .negative = true } } },
        },
        .{
            .instruction = .{ 0xCE, 0xFE, 0x3D }, // DEC $3DFE
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x3DFE, 0x2D }} },
            .after = .{ .cpu = .{ .pc = 0x0203 }, .memory = &[_]Tuple{.{ 0x3DFE, 0x2C }} },
        },
        .{
            .instruction = .{ 0xD6, 0xE3, 0x00 }, // DEC $E3, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x12 }, .memory = &[_]Tuple{.{ 0x00F5, 0xDE }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x12, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x00F5, 0xDD }} },
        },
        .{
            .instruction = .{ 0xDE, 0x2E, 0x12 }, // DEC $122E, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x25 }, .memory = &[_]Tuple{.{ 0x1253, 0x80 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0x25 }, .memory = &[_]Tuple{.{ 0x1253, 0x7F }} },
        },
        .{
            .instruction = .{ 0xE6, 0x8A, 0x00 }, // INC $8A
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0x008A, 0xAE }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x008A, 0xAF }} },
        },
        .{
            .instruction = .{ 0xE8, 0x00, 0x00 }, // INX
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x6A } },
            .after = .{ .cpu = .{ .pc = 0x0201, .xr = 0x6B } },
        },
        .{
            .instruction = .{ 0xEE, 0x08, 0xF3 }, // INC $F308
            .before = .{ .cpu = .{ .pc = 0x0200 }, .memory = &[_]Tuple{.{ 0xF308, 0x4F }} },
            .after = .{ .cpu = .{ .pc = 0x0203 }, .memory = &[_]Tuple{.{ 0xF308, 0x50 }} },
        },
        .{
            .instruction = .{ 0xF6, 0x09, 0x00 }, // INC $09, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x31 }, .memory = &[_]Tuple{.{ 0x003A, 0x7F }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .xr = 0x31, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x003A, 0x80 }} },
        },
        .{
            .instruction = .{ 0xFE, 0x23, 0x1F }, // INC $1F23, X
            .before = .{ .cpu = .{ .pc = 0x0200, .xr = 0x12 }, .memory = &[_]Tuple{.{ 0x1F35, 0xE4 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .xr = 0x12, .sr = .{ .negative = true } }, .memory = &[_]Tuple{.{ 0x1F35, 0xE5 }} },
        },
    };
    const success = try testCaseSet(&test_cases);
    try std.testing.expect(success);
}

test "arithmeticInstructions" {
    const test_cases = [_]TestCase{
        .{
            .instruction = .{ 0x61, 0x8A, 0x00 }, // ADC ($8A, X)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x3A, .xr = 0x27 }, .memory = &[_]Tuple{ .{ 0x00B1, 0xDE }, .{ 0x00B2, 0xDE }, .{ 0xDEDE, 0x41 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x7B, .xr = 0x27 }, .memory = &[_]Tuple{ .{ 0x00B1, 0xDE }, .{ 0x00B2, 0xDE }, .{ 0xDEDE, 0x41 } } },
        },
        .{
            .instruction = .{ 0x65, 0x61, 0x00 }, // ADC $61
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x7F }, .memory = &[_]Tuple{.{ 0x0061, 0x7F }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0xFE, .sr = .{ .overflow = true, .negative = true } }, .memory = &[_]Tuple{.{ 0x0061, 0x7F }} },
        },
        .{
            .instruction = .{ 0x69, 0x80, 0x00 }, // ADC #$80
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x80 } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x00, .sr = .{ .carry = true, .overflow = true, .zero = true } } },
        },
        .{
            .instruction = .{ 0x6D, 0xEF, 0xBE }, // ADC $BEEF
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x3E, .sr = .{ .carry = true } }, .memory = &[_]Tuple{.{ 0xBEEF, 0x01 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x40 }, .memory = &[_]Tuple{.{ 0xBEEF, 0x01 }} },
        },
        .{
            .instruction = .{ 0x71, 0xFE, 0x00 }, // ADC ($FE), Y (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x12, .yr = 0x05, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{ .{ 0x00FE, 0x06 }, .{ 0x00FF, 0xB0 }, .{ 0xB00B, 0x09 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x21, .yr = 0x05, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{ .{ 0x00FE, 0x06 }, .{ 0x00FF, 0xB0 }, .{ 0xB00B, 0x09 } } },
        },
        .{
            .instruction = .{ 0x75, 0x04, 0x00 }, // ADC $04, X (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x45, .xr = 0x03, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{.{ 0x0007, 0x45 }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x90, .xr = 0x03, .sr = .{ .decimal = true, .overflow = true, .negative = true } }, .memory = &[_]Tuple{.{ 0x0007, 0x45 }} },
        },
        .{
            .instruction = .{ 0x79, 0x79, 0xDE }, // ADC $DE79, Y (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x50, .yr = 0x34, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{.{ 0xDEAD, 0x50 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x00, .yr = 0x34, .sr = .{ .decimal = true, .negative = true, .carry = true } }, .memory = &[_]Tuple{.{ 0xDEAD, 0x50 }} },
        },
        .{
            .instruction = .{ 0x7D, 0x11, 0xD2 }, // ADC $D211, X (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x10, .xr = 0x99, .sr = .{ .decimal = true, .carry = true } }, .memory = &[_]Tuple{.{ 0xD2AA, 0x10 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x21, .xr = 0x99, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{.{ 0xD2AA, 0x10 }} },
        },
        .{
            .instruction = .{ 0xE1, 0x8A, 0x00 }, // SBC ($8A, X)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x3A, .xr = 0x27, .sr = .{ .carry = true } }, .memory = &[_]Tuple{ .{ 0x00B1, 0xDE }, .{ 0x00B2, 0xDE }, .{ 0xDEDE, 0x41 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0xF9, .xr = 0x27, .sr = .{ .negative = true } }, .memory = &[_]Tuple{ .{ 0x00B1, 0xDE }, .{ 0x00B2, 0xDE }, .{ 0xDEDE, 0x41 } } },
        },
        .{
            .instruction = .{ 0xE5, 0x61, 0x00 }, // SBC $61
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x7F, .sr = .{ .carry = true } }, .memory = &[_]Tuple{.{ 0x0061, 0x7F }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x00, .sr = .{ .zero = true, .carry = true } }, .memory = &[_]Tuple{.{ 0x0061, 0x7F }} },
        },
        .{
            .instruction = .{ 0xE9, 0x80, 0x00 }, // SBC #$80
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x81, .sr = .{ .carry = true } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x01, .sr = .{ .carry = true } } },
        },
        .{
            .instruction = .{ 0xED, 0xEF, 0xBE }, // SBC $BEEF
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x3E, .sr = .{ .carry = true } }, .memory = &[_]Tuple{.{ 0xBEEF, 0x01 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x3D, .sr = .{ .carry = true } }, .memory = &[_]Tuple{.{ 0xBEEF, 0x01 }} },
        },
        .{
            .instruction = .{ 0xF1, 0xFE, 0x00 }, // SBC ($FE), Y (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x12, .yr = 0x05, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{ .{ 0x00FE, 0x06 }, .{ 0x00FF, 0xB0 }, .{ 0xB00B, 0x09 } } },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x03, .yr = 0x05, .sr = .{ .decimal = true, .carry = true } }, .memory = &[_]Tuple{ .{ 0x00FE, 0x06 }, .{ 0x00FF, 0xB0 }, .{ 0xB00B, 0x09 } } },
        },
        .{
            .instruction = .{ 0xF5, 0x04, 0x00 }, // SBC $04, X (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x45, .xr = 0x03, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{.{ 0x0007, 0x45 }} },
            .after = .{ .cpu = .{ .pc = 0x0202, .ac = 0x99, .xr = 0x03, .sr = .{ .decimal = true, .negative = true } }, .memory = &[_]Tuple{.{ 0x0007, 0x45 }} },
        },
        .{
            .instruction = .{ 0xF9, 0x79, 0xDE }, // SBC $DE79, Y (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x50, .yr = 0x34, .sr = .{ .decimal = true } }, .memory = &[_]Tuple{.{ 0xDEAD, 0x51 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x98, .yr = 0x34, .sr = .{ .decimal = true, .negative = true } }, .memory = &[_]Tuple{.{ 0xDEAD, 0x51 }} },
        },
        .{
            .instruction = .{ 0xFD, 0x11, 0xD2 }, // SBC $D211, X (Decimal mode)
            .before = .{ .cpu = .{ .pc = 0x0200, .ac = 0x10, .xr = 0x99, .sr = .{ .decimal = true, .carry = true } }, .memory = &[_]Tuple{.{ 0xD2AA, 0x01 }} },
            .after = .{ .cpu = .{ .pc = 0x0203, .ac = 0x09, .xr = 0x99, .sr = .{ .decimal = true, .carry = true } }, .memory = &[_]Tuple{.{ 0xD2AA, 0x01 }} },
        },
    };
    const success = try testCaseSet(&test_cases);
    try std.testing.expect(success);
}
