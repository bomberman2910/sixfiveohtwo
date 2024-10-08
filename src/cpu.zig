const std = @import("std");
const bus = @import("./bus.zig");

const Bus = bus.Bus;

const testing_allocator = std.testing.allocator;

const CpuError = error{ illegal_opcode, not_implemented };

const Flags = packed struct { carry: bool = false, zero: bool = false, interrupt: bool = false, decimal: bool = false, break_bit: bool = false, ignored: bool = false, overflow: bool = false, negative: bool = false };

const DecodedInstruction = packed struct { c: u2, b: u3, a: u3 };

const OperandSource = union(enum) { operand_address: u16, immediate_operand: u8, is_ac: bool, is_implied: bool };
const OperandValue = union { byte: u8, address: u16 };

pub const State = struct { sr: Flags = .{}, ac: u8 = 0, xr: u8 = 0, yr: u8 = 0, sp: u8 = 0xFF, pc: u16 = 0xFFFC };

pub const Cpu = struct {
    state: State,
    bus: Bus,
    current_cycles: i8,
    total_cycles: i64,

    pub fn init(allocator: std.mem.Allocator) Cpu {
        const cpu = Cpu{ .state = .{}, .bus = Bus.init(allocator), .current_cycles = 0, .total_cycles = 0 };
        return cpu;
    }

    pub fn deinit(self: *Cpu) void {
        self.bus.deinit();
    }

    pub fn reset(self: *Cpu) !void {
        self.state = .{};
        const start_address = try self.readAddressFromProgramCounter();
        self.state.pc = start_address;
    }

    pub fn irq(self: *Cpu) !void {
        if (!self.state.sr.interrupt) {
            try self.interrupt();
            self.state.pc = try self.readAddressFromAddress(0xFFFA);
        }
    }

    pub fn nmi(self: *Cpu) !void {
        try self.interrupt();
        self.state.pc = try self.readAddressFromAddress(0xFFFE);
    }

    pub fn clock(self: *Cpu) !void {
        if (self.current_cycles > 0) {
            self.current_cycles -= 1;
            return;
        } else {
            const instruction = try self.readNextByte();
            const decoded: DecodedInstruction = @bitCast(instruction);

            const source: OperandSource = switch (decoded.b) {
                0 => switch (decoded.c) {
                    0 => switch (decoded.a) {
                        0, 2, 3 => block: {
                            self.current_cycles = 2;
                            break :block .{ .is_implied = true };
                        },
                        1 => block: {
                            self.current_cycles = 4;
                            break :block .{ .operand_address = try self.readAddressFromProgramCounter() };
                        },
                        5, 6, 7 => block: {
                            self.current_cycles = 2;
                            break :block .{ .immediate_operand = try self.readNextByte() };
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => block: {
                        self.current_cycles = 6;
                        break :block .{ .operand_address = try self.getZeroPageXIndirectAddress() };
                    },
                    2 => switch (decoded.a) {
                        5 => block: {
                            self.current_cycles = 2;
                            break :block .{ .immediate_operand = try self.readNextByte() };
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    else => return CpuError.illegal_opcode,
                },
                1 => switch (decoded.c) {
                    0 => switch (decoded.a) {
                        0, 2, 3 => return CpuError.illegal_opcode,
                        else => block: {
                            self.current_cycles = 3;
                            break :block .{ .operand_address = try self.readNextByte() };
                        },
                    },
                    1, 2 => block: {
                        self.current_cycles = 3;
                        break :block .{ .operand_address = try self.readNextByte() };
                    },
                    else => return CpuError.illegal_opcode,
                },
                2 => switch (decoded.c) {
                    0 => block: {
                        self.current_cycles = 2;
                        break :block .{ .is_implied = true };
                    },
                    1 => switch (decoded.a) {
                        4 => return CpuError.illegal_opcode,
                        else => block: {
                            self.current_cycles = 2;
                            break :block .{ .immediate_operand = try self.readNextByte() };
                        },
                    },
                    2 => switch (decoded.a) {
                        0...3 => block: {
                            self.current_cycles = 2;
                            break :block .{ .is_ac = true };
                        },
                        4...7 => block: {
                            self.current_cycles = 2;
                            break :block .{ .is_implied = true };
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                3 => switch (decoded.c) {
                    0 => switch (decoded.a) {
                        0 => return CpuError.illegal_opcode,
                        else => block: {
                            self.current_cycles = 4;
                            break :block .{ .operand_address = try self.readAddressFromProgramCounter() };
                        },
                    },
                    1, 2 => block: {
                        self.current_cycles = 4;
                        break :block .{ .operand_address = try self.readAddressFromProgramCounter() };
                    },
                    else => return CpuError.illegal_opcode,
                },
                4 => switch (decoded.c) {
                    0 => block: {
                        self.current_cycles = 2;
                        break :block .{ .immediate_operand = try self.readNextByte() };
                    },
                    1 => block: {
                        self.current_cycles = 5; // TODO page boundary crossing is ignored here
                        break :block .{ .operand_address = try self.getZeroPageYIndirectAddress() };
                    },
                    else => return CpuError.illegal_opcode,
                },
                5 => switch (decoded.c) {
                    0 => switch (decoded.a) {
                        4, 5 => block: {
                            self.current_cycles = 4;
                            break :block .{ .operand_address = try self.getZeroPageXAddress() };
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => block: {
                        self.current_cycles = 6;
                        break :block .{ .operand_address = try self.getZeroPageXAddress() };
                    },
                    2 => switch (decoded.a) {
                        4, 5 => block: {
                            self.current_cycles = 4;
                            break :block .{ .operand_address = try self.getZeroPageYAddress() };
                        },
                        else => block: {
                            self.current_cycles = 4;
                            break :block .{ .operand_address = try self.getZeroPageXAddress() };
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                6 => switch (decoded.c) {
                    0 => block: {
                        self.current_cycles = 2;
                        break :block .{ .is_implied = true };
                    },
                    1 => block: {
                        self.current_cycles = 4; // TODO page boundary crossing is ignored here
                        break :block .{ .operand_address = try self.getAbsoluteYAddress() };
                    },
                    2 => switch (decoded.a) {
                        4, 5 => block: {
                            self.current_cycles = 2;
                            break :block .{ .is_implied = true };
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    else => return CpuError.illegal_opcode,
                },
                7 => switch (decoded.c) {
                    0 => switch (decoded.a) {
                        5 => block: {
                            self.current_cycles = 4; // TODO page boundary crossing is ignored here
                            break :block .{ .operand_address = try self.getAbsoluteXAddress() };
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => block: {
                        self.current_cycles = 4; // TODO page boundary crossing is ignored here
                        break :block .{ .operand_address = try self.getAbsoluteXAddress() };
                    },
                    2 => switch (decoded.a) {
                        4 => return CpuError.illegal_opcode,
                        5 => block: {
                            self.current_cycles = 4; // TODO page boundary crossing is ignored here
                            break :block .{ .operand_address = try self.getAbsoluteYAddress() };
                        },
                        else => block: {
                            self.current_cycles = 4; // TODO page boundary crossing is ignored here
                            break :block .{ .operand_address = try self.getAbsoluteXAddress() };
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
            };

            const operand: ?OperandValue = switch (source) {
                .operand_address => |address| switch (instruction) {
                    0x6C => .{ .address = try self.readAddressFromAddressInsidePage(address) }, // JMP ind needs an address as operand, that is read from the given operand address
                    0x20, 0x4C, 0x81, 0x84, 0x85, 0x86, 0x8C, 0x8D, 0x8E, 0x91, 0x94, 0x95, 0x96, 0x99, 0x9D, 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE => .{ .address = address }, // JMP abs, all store instructions and increment/decrement use the operand address as a destination
                    else => .{ .byte = try self.bus.read(address) },
                },
                .immediate_operand => |value| .{ .byte = value },
                .is_implied => null,
                .is_ac => .{ .byte = self.state.ac },
            };

            switch (decoded.a) {
                0 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        0 => { // BRK
                            self.current_cycles += 5;
                            self.state.pc = @addWithOverflow(self.state.pc, 2)[0];
                            self.state.sr.break_bit = true;
                            try self.nmi();
                            self.state.sr.break_bit = false;
                        },
                        2 => { // PHP
                            self.current_cycles += 1;
                            var sr = self.state.sr;
                            sr.break_bit = true;
                            sr.ignored = true;
                            try self.pushToStack(@bitCast(sr));
                        },
                        4 => { // BPL
                            if (!self.state.sr.negative)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // CLC
                            self.state.sr.carry = false;
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => self.orA(operand.?.byte), // ORA
                    2 => switch (decoded.b) {
                        0, 4, 6 => return CpuError.illegal_opcode,
                        else => { // ASL
                            const shifted = @shlWithOverflow(operand.?.byte, 1);
                            self.state.sr.carry = shifted[1] == 1;
                            self.checkNegativeAndZeroFlags(shifted[0]);
                            switch (source) {
                                .is_ac => {
                                    self.state.ac = shifted[0];
                                },
                                .operand_address => |address| {
                                    self.current_cycles += 2;
                                    try self.bus.write(address, shifted[0]);
                                },
                                else => return CpuError.illegal_opcode,
                            }
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                1 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        0 => { // JSR
                            self.current_cycles += 2;
                            try self.pushToStack(@intCast(@subWithOverflow(self.state.pc, 1)[0] >> 8));
                            const destination = try self.readAddressFromAddress(@subWithOverflow(self.state.pc, 2)[0]);
                            try self.pushToStack(@intCast(@subWithOverflow(self.state.pc, 1)[0] & 0xFF));
                            self.state.pc = destination;
                        },
                        1, 3 => { // BIT
                            self.state.sr.negative = operand.?.byte & 0x80 == 0x80;
                            self.state.sr.overflow = operand.?.byte & 0x40 == 0x40;
                            self.state.sr.zero = self.state.ac & operand.?.byte == 0;
                        },
                        2 => { // PLP
                            self.current_cycles += 2;
                            var sr: Flags = @bitCast(try self.pullFromStack());
                            sr.break_bit = false;
                            sr.ignored = true;
                            self.state.sr = sr;
                        },
                        4 => { // BMI
                            if (self.state.sr.negative)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // SEC
                            self.state.sr.carry = true;
                        },
                        5, 7 => return CpuError.illegal_opcode,
                    },
                    1 => self.andA(operand.?.byte), // AND
                    2 => switch (decoded.b) {
                        0, 4, 6 => return CpuError.illegal_opcode,
                        else => { // ROL
                            const shifted = @shlWithOverflow(operand.?.byte, 1);
                            var result = shifted[0];
                            if (self.state.sr.carry)
                                result |= 0x01;
                            self.state.sr.carry = shifted[1] == 1;
                            self.checkNegativeAndZeroFlags(result);
                            switch (source) {
                                .is_ac => {
                                    self.state.ac = result;
                                },
                                .operand_address => |address| {
                                    self.current_cycles += 2;
                                    try self.bus.write(address, result);
                                },
                                else => return CpuError.illegal_opcode,
                            }
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                2 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        0 => { // RTI
                            self.current_cycles += 4;
                            const old_ignored = self.state.sr.ignored;
                            var sr = try self.pullFromStack();
                            sr &= 0xCF;
                            self.state.sr = @bitCast(sr);
                            self.state.sr.ignored = old_ignored;
                            const low_byte = try self.pullFromStack();
                            const high_byte = try self.pullFromStack();
                            const destination = (@as(u16, high_byte) << 8) + low_byte;
                            self.state.pc = destination;
                        },
                        2 => { // PHA
                            self.current_cycles += 1;
                            try self.pushToStack(self.state.ac);
                        },
                        3 => { // JMP abs
                            self.current_cycles -= 1;
                            self.state.pc = operand.?.address;
                        },
                        4 => { // BVC
                            if (!self.state.sr.overflow)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // CLI
                            self.state.sr.interrupt = false;
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => self.eorA(operand.?.byte),
                    2 => switch (decoded.b) {
                        0, 4, 6 => return CpuError.illegal_opcode,
                        else => { // LSR
                            const least_significant_bit = operand.?.byte & 0x01;
                            const shifted = operand.?.byte >> 1;
                            self.state.sr.carry = least_significant_bit == 1;
                            self.checkNegativeAndZeroFlags(shifted);
                            switch (source) {
                                .is_ac => {
                                    self.state.ac = shifted;
                                },
                                .operand_address => |address| {
                                    self.current_cycles += 2;
                                    try self.bus.write(address, shifted);
                                },
                                else => return CpuError.illegal_opcode,
                            }
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                3 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        0 => { // RTS
                            self.current_cycles += 4;
                            const low_byte = try self.pullFromStack();
                            const high_byte = try self.pullFromStack();
                            const destination = (@as(u16, high_byte) << 8) + low_byte;
                            self.state.pc = @addWithOverflow(destination, 1)[0];
                        },
                        2 => { // PLA
                            self.current_cycles += 2;
                            self.state.ac = try self.pullFromStack();
                            self.checkNegativeAndZeroFlags(self.state.ac);
                        },
                        3 => { // JMP (ind)
                            self.current_cycles += 1;
                            self.state.pc = operand.?.address;
                        },
                        4 => { // BVS
                            if (self.state.sr.overflow)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // SEI
                            self.state.sr.interrupt = true;
                        },
                        else => return CpuError.illegal_opcode,
                    },
                    1 => self.addWithCarry(operand.?.byte),
                    2 => switch (decoded.b) {
                        0, 4, 6 => return CpuError.illegal_opcode,
                        else => { // ROR
                            const least_significant_bit = operand.?.byte & 0x01;
                            var shifted = operand.?.byte >> 1;
                            if (self.state.sr.carry)
                                shifted |= 0x80;
                            self.state.sr.carry = least_significant_bit == 1;
                            self.checkNegativeAndZeroFlags(shifted);
                            switch (source) {
                                .is_ac => {
                                    self.state.ac = shifted;
                                },
                                .operand_address => |address| {
                                    self.current_cycles += 2;
                                    try self.bus.write(address, shifted);
                                },
                                else => return CpuError.illegal_opcode,
                            }
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                4 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        0, 7 => return CpuError.illegal_opcode,
                        2 => { // DEY
                            self.state.yr = @subWithOverflow(self.state.yr, 1)[0];
                            self.checkNegativeAndZeroFlags(self.state.yr);
                        },
                        4 => { // BCC
                            if (!self.state.sr.carry)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // TYA
                            self.state.ac = self.state.yr;
                            self.checkNegativeAndZeroFlags(self.state.ac);
                        },
                        else => { // STY
                            try self.bus.write(operand.?.address, self.state.yr);
                        },
                    },
                    1 => {
                        try self.bus.write(operand.?.address, self.state.ac);
                    },
                    2 => switch (decoded.b) {
                        0, 4, 7 => return CpuError.illegal_opcode,
                        2 => { // TXA
                            self.state.ac = self.state.xr;
                            self.checkNegativeAndZeroFlags(self.state.ac);
                        },
                        6 => { // TXS
                            self.state.sp = self.state.xr;
                        },
                        else => { // STX
                            try self.bus.write(operand.?.address, self.state.xr);
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                5 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        2 => { // TAY
                            self.state.yr = self.state.ac;
                            self.checkNegativeAndZeroFlags(self.state.yr);
                        },
                        4 => { // BCS
                            if (self.state.sr.carry)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // CLV
                            self.state.sr.overflow = false;
                        },
                        else => { // LDY
                            self.state.yr = operand.?.byte;
                            self.checkNegativeAndZeroFlags(self.state.yr);
                        },
                    },
                    1 => { // LDA
                        self.state.ac = operand.?.byte;
                        self.checkNegativeAndZeroFlags(self.state.ac);
                    },
                    2 => switch (decoded.b) {
                        2 => { // TAX
                            self.state.xr = self.state.ac;
                            self.checkNegativeAndZeroFlags(self.state.xr);
                        },
                        4 => return CpuError.illegal_opcode,
                        6 => { // TSX
                            self.state.xr = self.state.sp;
                            self.checkNegativeAndZeroFlags(self.state.xr);
                        },
                        else => { // LDX
                            self.state.xr = operand.?.byte;
                            self.checkNegativeAndZeroFlags(self.state.xr);
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                6 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        2 => { // INY
                            self.state.yr = @addWithOverflow(self.state.yr, 1)[0];
                            self.checkNegativeAndZeroFlags(self.state.yr);
                        },
                        4 => { // BNE
                            if (!self.state.sr.zero)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // CLD
                            self.state.sr.decimal = false;
                        },
                        5, 7 => return CpuError.illegal_opcode,
                        else => { // CPY
                            self.state.sr.carry = self.state.yr >= operand.?.byte;
                            self.state.sr.negative = @subWithOverflow(self.state.yr, operand.?.byte)[0] & 0x80 == 0x80;
                            self.state.sr.zero = self.state.yr == operand.?.byte;
                        },
                    },
                    1 => { // CMP
                        self.state.sr.carry = self.state.ac >= operand.?.byte;
                        self.state.sr.negative = @subWithOverflow(self.state.ac, operand.?.byte)[0] & 0x80 == 0x80;
                        self.state.sr.zero = self.state.ac == operand.?.byte;
                    },
                    2 => switch (decoded.b) {
                        2 => { // DEX
                            self.state.xr = @subWithOverflow(self.state.xr, 1)[0];
                            self.checkNegativeAndZeroFlags(self.state.xr);
                        },
                        0, 4, 6 => return CpuError.illegal_opcode,
                        else => { // DEC
                            self.current_cycles += 2;
                            try self.decrementValue(operand.?.address);
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
                7 => switch (decoded.c) {
                    0 => switch (decoded.b) {
                        2 => { // INX
                            self.state.xr = @addWithOverflow(self.state.xr, 1)[0];
                            self.checkNegativeAndZeroFlags(self.state.xr);
                        },
                        4 => { // BEQ
                            if (self.state.sr.zero)
                                self.branch(@as(i8, @bitCast(operand.?.byte)));
                        },
                        6 => { // SED
                            self.state.sr.decimal = true;
                        },
                        5, 7 => return CpuError.illegal_opcode,
                        else => { // CPX
                            self.state.sr.carry = self.state.xr >= operand.?.byte;
                            self.state.sr.negative = @subWithOverflow(self.state.xr, operand.?.byte)[0] & 0x80 == 0x80;
                            self.state.sr.zero = self.state.xr == operand.?.byte;
                        },
                    },
                    1 => { // SBC
                        self.subWithBorrow(operand.?.byte);
                    },
                    2 => switch (decoded.b) {
                        0, 4, 6 => return CpuError.illegal_opcode,
                        2 => {}, // NOP
                        else => { // INC
                            self.current_cycles += 2;
                            try self.incrementValue(operand.?.address);
                        },
                    },
                    else => return CpuError.illegal_opcode,
                },
            }
            self.total_cycles += self.current_cycles;
        }
        self.bus.clock();
    }

    fn todo() CpuError!void {
        return CpuError.not_implemented;
    }

    fn pushToStack(self: *Cpu, value: u8) !void {
        try self.bus.write(0x0100 + @as(u16, self.state.sp), value);
        self.state.sp = @subWithOverflow(self.state.sp, 1)[0];
    }

    fn pullFromStack(self: *Cpu) !u8 {
        self.state.sp = @addWithOverflow(self.state.sp, 1)[0];
        const value = try self.bus.read(0x0100 + @as(u16, self.state.sp));
        return value;
    }

    fn interrupt(self: *Cpu) !void {
        try self.pushToStack(@intCast(@subWithOverflow(self.state.pc, 1)[0] >> 8));
        try self.pushToStack(@intCast(@subWithOverflow(self.state.pc, 1)[0] & 0xFF));
        try self.pushToStack(@bitCast(self.state.sr));
        self.state.sr.interrupt = true;
    }

    fn branch(self: *Cpu, distance: i8) void {
        const distance_value = @abs(distance);

        self.current_cycles += 1; // TODO page boundary crossing is ignored here

        if (distance >= 0) {
            self.state.pc = @addWithOverflow(self.state.pc, distance_value)[0];
        } else {
            self.state.pc = @subWithOverflow(self.state.pc, distance_value)[0];
        }
    }

    fn eorA(self: *Cpu, operand: u8) void {
        self.state.ac = self.state.ac ^ operand;
        self.checkNegativeAndZeroFlags(self.state.ac);
    }

    fn andA(self: *Cpu, operand: u8) void {
        self.state.ac = self.state.ac & operand;
        self.checkNegativeAndZeroFlags(self.state.ac);
    }

    fn orA(self: *Cpu, operand: u8) void {
        self.state.ac = self.state.ac | operand;
        self.checkNegativeAndZeroFlags(self.state.ac);
    }

    fn subWithBorrow(self: *Cpu, operand: u8) void {
        const old_ac = self.state.ac;
        const old_carry = self.state.sr.carry;

        self.addWithCarry(~operand);
        self.checkNegativeAndZeroFlags(self.state.ac);

        if (self.state.sr.decimal) {
            var result_low: i16 = @as(i16, old_ac & 0x0F) - (operand & 0x0F);
            if (!old_carry)
                result_low -= 1;
            if (result_low < 0)
                result_low = ((result_low - 0x06) & 0x0F) - 0x10;
            var result: i16 = @as(i16, old_ac & 0xF0) - (operand & 0xF0) + result_low;
            self.state.sr.carry = result >= 0;
            self.state.sr.negative = result & 0x80 == 0x80;
            if (result < 0) {
                result -= 0x60;
            }
            self.state.ac = @intCast(result & 0xFF);
        }
    }

    fn addWithCarry(self: *Cpu, operand: u8) void {
        const sign_ac = self.state.ac & 0x80;
        const sign_op = operand & 0x80;
        if (self.state.sr.decimal) {
            var binary_result = @addWithOverflow(self.state.ac, operand);
            if (self.state.sr.carry)
                binary_result = @addWithOverflow(binary_result[0], @as(u8, 1));
            self.state.sr.zero = binary_result[0] == 0x00;

            var result_low = (self.state.ac & 0x0F) + (operand & 0x0F) + (@as(u8, @bitCast(self.state.sr)) & 0x01);
            if (result_low >= 0x0A)
                result_low = ((result_low + 0x06) & 0x0F) + 0x10;
            var result = @as(u16, (self.state.ac & 0xF0)) + (operand & 0xF0) + result_low;
            const sign_result = result & 0x80;
            self.state.sr.overflow = (sign_ac == sign_op) and (sign_ac != sign_result);
            self.state.sr.negative = (result & 0x80) == 0x80;
            if (result >= 0xA0)
                result += 0x60;
            self.state.ac = @intCast(result & 0xFF);
            self.state.sr.carry = result >= 0x100;
        } else {
            const result = @addWithOverflow(self.state.ac, operand);
            if (self.state.sr.carry) {
                const result_with_carry = @addWithOverflow(result[0], @as(u8, 1));
                self.state.ac = result_with_carry[0];
                self.state.sr.carry = result_with_carry[1] == 1 or result[1] == 1;
            } else {
                self.state.ac = result[0];
                self.state.sr.carry = result[1] == 1;
            }
            self.checkNegativeAndZeroFlags(self.state.ac);
            const sign_result = self.state.ac & 0x80;
            self.state.sr.overflow = (sign_ac == sign_op) and (sign_ac != sign_result);
        }
    }

    fn decrementValue(self: *Cpu, address: u16) !void {
        var value = try self.bus.read(address);
        value = @subWithOverflow(value, 1)[0];
        try self.bus.write(address, value);
        self.checkNegativeAndZeroFlags(value);
    }

    fn incrementValue(self: *Cpu, address: u16) !void {
        var value = try self.bus.read(address);
        value = @addWithOverflow(value, 1)[0];
        try self.bus.write(address, value);
        self.checkNegativeAndZeroFlags(value);
    }

    fn readNextByte(self: *Cpu) !u8 {
        const value = self.bus.read(self.state.pc);
        self.state.pc = @addWithOverflow(self.state.pc, 1)[0];
        return value;
    }

    fn getAbsoluteXAddress(self: *Cpu) !u16 {
        const base_address = try self.readAddressFromProgramCounter();
        const actual_address = @addWithOverflow(base_address, self.state.xr)[0];
        return actual_address;
    }

    fn getAbsoluteYAddress(self: *Cpu) !u16 {
        const base_address = try self.readAddressFromProgramCounter();
        const actual_address = @addWithOverflow(base_address, self.state.yr)[0];
        return actual_address;
    }

    fn getZeroPageXAddress(self: *Cpu) !u8 {
        const base_address = try self.readNextByte();
        const actual_address = @addWithOverflow(base_address, self.state.xr)[0];
        return actual_address;
    }

    fn getZeroPageYAddress(self: *Cpu) !u8 {
        const base_address = try self.readNextByte();
        const actual_address = @addWithOverflow(base_address, self.state.yr)[0];
        return actual_address;
    }

    fn getIndirectAddress(self: *Cpu) !u16 {
        const source_address = try self.readAddressFromProgramCounter();
        const actual_address = try self.readAddressFromAddress(source_address);
        return actual_address;
    }

    fn getZeroPageXIndirectAddress(self: *Cpu) !u16 {
        var zero_page_address = try self.readNextByte();
        zero_page_address = @addWithOverflow(zero_page_address, self.state.xr)[0];
        return (@as(u16, try self.bus.read(@addWithOverflow(zero_page_address, 1)[0])) << 8) + try self.bus.read(zero_page_address);
    }

    fn getZeroPageYIndirectAddress(self: *Cpu) !u16 {
        const zero_page_address = try self.readNextByte();
        var actual_address = (@as(u16, try self.bus.read(@addWithOverflow(zero_page_address, 1)[0])) << 8) + try self.bus.read(zero_page_address);
        actual_address = @addWithOverflow(actual_address, self.state.yr)[0];
        return actual_address;
    }

    fn readAddressFromProgramCounter(self: *Cpu) !u16 {
        const value = try self.readAddressFromAddress(self.state.pc);
        self.state.pc = @addWithOverflow(self.state.pc, 2)[0];
        return value;
    }

    fn readAddressFromAddress(self: *Cpu, address: u16) !u16 {
        const low_byte = try self.bus.read(address);
        const high_byte = try self.bus.read(@addWithOverflow(address, 1)[0]);
        const value = (@as(u16, high_byte) << 8) + low_byte;
        return value;
    }

    fn readAddressFromAddressInsidePage(self: *Cpu, address: u16) !u16 {
        const low_byte = try self.bus.read(address);
        var high_byte: u8 = undefined;
        if (address & 0xFF == 0xFF) {
            high_byte = try self.bus.read(address - 0xFF);
        } else {
            high_byte = try self.bus.read(@addWithOverflow(address, 1)[0]);
        }
        const value = (@as(u16, high_byte) << 8) + low_byte;
        return value;
    }

    fn checkNegativeAndZeroFlags(self: *Cpu, value: u8) void {
        self.state.sr.zero = value == 0;
        self.state.sr.negative = (value & 0x80) == 0x80;
    }
};

test "getNextByte" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x8C);

    const output = try cpu.readNextByte();
    try std.testing.expectEqual(output, 0x8C);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "getAbsoluteXAddress" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x40);
    try cpu.bus.write(0xFFFD, 0x02);

    cpu.state.xr = 8;

    const output = try cpu.getAbsoluteXAddress();
    try std.testing.expectEqual(0x0248, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFE);
}

test "getAbsoluteYAddress" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x40);
    try cpu.bus.write(0xFFFD, 0x02);

    cpu.state.yr = 8;

    const output = try cpu.getAbsoluteYAddress();
    try std.testing.expectEqual(0x0248, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFE);
}

test "getZeroPageXAddress" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x48);

    cpu.state.xr = 3;

    const output = try cpu.getZeroPageXAddress();
    try std.testing.expectEqual(0x4B, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "getZeroPageYAddress" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x48);

    cpu.state.yr = 3;

    const output = try cpu.getZeroPageYAddress();
    try std.testing.expectEqual(0x4B, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "getIndirectValue" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x4B);
    try cpu.bus.write(0xFFFD, 0x02);

    try cpu.bus.addDevice(0x0200, 0xFF, null, false);
    try cpu.bus.write(0x024B, 0x62);
    try cpu.bus.write(0x024C, 0x02);

    const output = try cpu.getIndirectAddress();
    try std.testing.expectEqual(0x0262, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFE);
}

test "getZeroPageXIndirectValue" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x45);

    try cpu.bus.addDevice(0x0000, 0xFF, null, false);
    try cpu.bus.write(0x0048, 0x31);
    try cpu.bus.write(0x0049, 0x80);

    cpu.state.xr = 3;

    const output = try cpu.getZeroPageXIndirectAddress();
    try std.testing.expectEqual(0x8031, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "getZeroPageXIndirectValueFromFF" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0xFC);

    try cpu.bus.addDevice(0x0000, 0x100, null, false);
    try cpu.bus.write(0x00FF, 0x31);
    try cpu.bus.write(0x0000, 0x80);

    cpu.state.xr = 3;

    const output = try cpu.getZeroPageXIndirectAddress();
    try std.testing.expectEqual(0x8031, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "getZeroPageYIndirectValue" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0xFFFA, 6, null, false);
    try cpu.bus.write(0xFFFC, 0x45);

    try cpu.bus.addDevice(0x0000, 0xFF, null, false);
    try cpu.bus.write(0x0045, 0x31);
    try cpu.bus.write(0x0046, 0x80);

    cpu.state.yr = 3;

    const output = try cpu.getZeroPageYIndirectAddress();
    try std.testing.expectEqual(0x8034, output);
    try std.testing.expectEqual(cpu.state.pc, 0xFFFD);
}

test "readAddressFromProgramCounter" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();
    try cpu.bus.addDevice(0x0000, 0x10000, null, false);
    try cpu.bus.write(0x8000, 0x0B);
    try cpu.bus.write(0x8001, 0xB0);

    cpu.state.pc = 0x8000;

    const value = try cpu.readAddressFromProgramCounter();
    try std.testing.expectEqual(0xB00B, value);
}

test "readAddressFromProgramCounterAtEndOfMemory" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();

    try cpu.bus.addDevice(0x0000, 0x10000, null, false);
    try cpu.bus.write(0xFFFF, 0x0B);
    try cpu.bus.write(0x0000, 0xB0);

    cpu.state.pc = 0xFFFF;

    const value = try cpu.readAddressFromProgramCounter();
    try std.testing.expectEqual(0xB00B, value);
}

test "checkNegativeAndZeroFlags" {
    var cpu = Cpu.init(testing_allocator);
    defer cpu.deinit();

    const TestCase = struct { value: u8, zero: bool, negative: bool };

    const test_cases = [_]TestCase{ .{ .value = 0, .zero = true, .negative = false }, .{ .value = 127, .zero = false, .negative = false }, .{ .value = 128, .zero = false, .negative = true }, .{ .value = 255, .zero = false, .negative = true } };

    for (test_cases) |test_case| {
        cpu.checkNegativeAndZeroFlags(test_case.value);
        // std.debug.print("\n0x{x} -> N={1} Z={2}\n", .{ test_case.value, cpu.state.sr.negative, cpu.state.sr.zero });
        try std.testing.expectEqual(test_case.negative, cpu.state.sr.negative);
        try std.testing.expectEqual(test_case.zero, cpu.state.sr.zero);
    }
}
