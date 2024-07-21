const std = @import("std");
const processor = @import("../cpu.zig");

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
    const FailedTestInformation = struct { counter: u16, expected_result: TestCase, actual_state: State, actual_memory: []const Tuple };
    var failed_tests = std.ArrayList(FailedTestInformation).init(testing_allocator);
    defer failed_tests.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(testing_allocator);
    defer {
        _ = arena_allocator.reset(std.heap.ArenaAllocator.ResetMode.free_all);
        arena_allocator.deinit();
    }

    var counter: u16 = 0;
    var failed: u16 = 0;
    var successful: u16 = 0;

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
            try failed_tests.append(.{ .counter = counter, .expected_result = test_case, .actual_state = cpu.state, .actual_memory = actual_memory_slice });
            all_tests_successful = false;
            failed += 1;
        } else {
            successful += 1;
        }
        counter += 1;
    }

    if (!all_tests_successful) {
        std.debug.print("\n", .{});
        for (failed_tests.items) |failed_test| {
            std.debug.print(
                \\----------------------------------------------------------
                \\failed test {d} for instruction {X} {X} {X}
                \\          PC  AC XR YR SP NV-BDIZC
                \\initial  {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\actual   {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\expected {X:0>4} {X:0>2} {X:0>2} {X:0>2} {X:0>2} {b:0>8} {s}
                \\
                \\
            , .{
                failed_test.counter,
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
                    var buffer = [_]u8{0} ** 120;
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
                    var buffer = [_]u8{0} ** 120;
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
                    var buffer = [_]u8{0} ** 120;
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
    std.debug.print("\nRan {d} tests: {d} sucessful and {d} failed\n", .{ counter, successful, failed });

    return all_tests_successful;
}

test "<test name here>" {
    const test_cases = [_]TestCase{
        <test cases here>
    };
    const success = try testCaseSet(&test_cases);
    try std.testing.expect(success);
}