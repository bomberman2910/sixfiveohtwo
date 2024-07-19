const std = @import("std");
const bus = @import("./bus.zig");

const Bus = bus.Bus;

const testing_allocator = std.testing.allocator;

const CpuError = error{illegal_opcode};

const Flags = packed struct { carry: bool = false, zero: bool = false, interrupt: bool = false, decimal: bool = false, break_bit: bool = false, ignored: bool = false, overflow: bool = false, negative: bool = false };

pub const State = struct { sr: Flags = .{}, ac: u8 = 0, xr: u8 = 0, yr: u8 = 0, sp: u8 = 0xFF, pc: u16 = 0xFFFC };

pub const Cpu = struct {
    state: State,
    bus: Bus,

    pub fn init(allocator: std.mem.Allocator) Cpu {
        const cpu = Cpu{ .state = .{}, .bus = Bus.init(allocator) };
        return cpu;
    }

    pub fn deinit(self: *Cpu) void {
        self.bus.deinit();
    }

    pub fn reset(self: *Cpu) !void {
        self.state = .{};
        const start_address = self.readAddressFromProgramCounter();
        self.state.pc = start_address;
    }

    pub fn clock(self: *Cpu) !void {
        const instruction = try self.readNextByte();
        switch (instruction) {
            0x01 => { // ORA X,ind
                const operand_address = try self.getZeroPageXIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x05 => { // ORA zpg
                const operand_address = try self.readNextByte();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x08 => { // PHP
                var sr = self.state.sr;
                sr.break_bit = true;
                sr.ignored = true;
                try self.bus.write(0x0100 + @as(u16, self.state.sp), @bitCast(sr));
                self.state.sp = @subWithOverflow(self.state.sp, 1)[0];
            },
            0x09 => { // ORA imm
                const operand = try self.readNextByte();
                self.orA(operand);
            },
            0x0D => { // ORA abs
                const operand_address = try self.readAddressFromProgramCounter();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x11 => { // ORA ind,Y
                const operand_address = try self.getZeroPageYIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x15 => { // ORA zpg,X
                const operand_address = try self.getZeroPageXAddress();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x19 => { // ORA abs,Y
                const operand_address = try self.getAbsoluteYAddress();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x1D => { // ORA abs,X
                const operand_address = try self.getAbsoluteXAddress();
                const operand = try self.bus.read(operand_address);
                self.orA(operand);
            },
            0x21 => { // AND X,ind
                const operand_address = try self.getZeroPageXIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x25 => { // AND zpg
                const operand_address = try self.readNextByte();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x28 => { // PLP
                self.state.sp = @addWithOverflow(self.state.sp, 1)[0];
                var sr: Flags = @bitCast(try self.bus.read(0x0100 + @as(u16, self.state.sp)));
                sr.break_bit = false;
                sr.ignored = true;
                self.state.sr = sr;
            },
            0x29 => { // AND imm
                const operand = try self.readNextByte();
                self.andA(operand);
            },
            0x2D => { // AND abs
                const operand_address = try self.readAddressFromProgramCounter();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x31 => { // AND ind,Y
                const operand_address = try self.getZeroPageYIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x35 => { // AND zpg,X
                const operand_address = try self.getZeroPageXAddress();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x39 => { // AND abs,Y
                const operand_address = try self.getAbsoluteYAddress();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x3D => { // AND abs,X
                const operand_address = try self.getAbsoluteXAddress();
                const operand = try self.bus.read(operand_address);
                self.andA(operand);
            },
            0x41 => { // EOR X,ind
                const operand_address = try self.getZeroPageXIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x45 => { // EOR zpg
                const operand_address = try self.readNextByte();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x48 => { // PHA
                try self.bus.write(0x0100 + @as(u16, self.state.sp), self.state.ac);
                self.state.sp = @subWithOverflow(self.state.sp, 1)[0];
            },
            0x49 => { // EOR imm
                const operand = try self.readNextByte();
                self.eorA(operand);
            },
            0x4D => { // EOR abs
                const operand_address = try self.readAddressFromProgramCounter();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x51 => { // EOR ind,Y
                const operand_address = try self.getZeroPageYIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x55 => { // EOR zpg,X
                const operand_address = try self.getZeroPageXAddress();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x59 => { // EOR abs,Y
                const operand_address = try self.getAbsoluteYAddress();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x5D => { // EOR abs,X
                const operand_address = try self.getAbsoluteXAddress();
                const operand = try self.bus.read(operand_address);
                self.eorA(operand);
            },
            0x61 => { // ADC X,ind
                const operand_address = try self.getZeroPageXIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x65 => { // ADC zpg
                const operand_address = try self.readNextByte();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x68 => { // PLA
                self.state.sp = @addWithOverflow(self.state.sp, 1)[0];
                self.state.ac = try self.bus.read(0x0100 + @as(u16, self.state.sp));
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0x69 => { // ADC imm
                const operand = try self.readNextByte();
                self.addWithCarry(operand);
            },
            0x6D => { // ADC abs
                const operand_address = try self.readAddressFromProgramCounter();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x71 => { // ADC ind,Y
                const operand_address = try self.getZeroPageYIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x75 => { // ADC zpg,X
                const operand_address = try self.getZeroPageXAddress();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x79 => { // ADC abs,Y
                const operand_address = try self.getAbsoluteYAddress();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x7D => { // ADC abs,X
                const operand_address = try self.getAbsoluteXAddress();
                const operand = try self.bus.read(operand_address);
                self.addWithCarry(operand);
            },
            0x81 => { // STA X,ind
                const destination_address = try self.getZeroPageXIndirectAddress();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x84 => { // STY zpg
                const destination_address = try self.readNextByte();
                try self.bus.write(destination_address, self.state.yr);
            },
            0x85 => { // STA zpg
                const destination_address = try self.readNextByte();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x86 => { // STX zpg
                const destination_address = try self.readNextByte();
                try self.bus.write(destination_address, self.state.xr);
            },
            0x88 => { // DEY
                self.state.yr = @subWithOverflow(self.state.yr, 1)[0];
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0x8A => { // TXA
                self.state.ac = self.state.xr;
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0x8C => { // STY abs
                const destination_address = try self.readAddressFromProgramCounter();
                try self.bus.write(destination_address, self.state.yr);
            },
            0x8D => { // STA abs
                const destination_address = try self.readAddressFromProgramCounter();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x8E => { // STX abs
                const destination_address = try self.readAddressFromProgramCounter();
                try self.bus.write(destination_address, self.state.xr);
            },
            0x91 => { // STA ind,Y
                const destination_address = try self.getZeroPageYIndirectAddress();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x94 => { // STY zpg,X
                const destination_address = try self.getZeroPageXAddress();
                try self.bus.write(destination_address, self.state.yr);
            },
            0x95 => { // STA zpg,X
                const destination_address = try self.getZeroPageXAddress();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x96 => { // STX zpg,Y
                const destination_address = try self.getZeroPageYAddress();
                try self.bus.write(destination_address, self.state.xr);
            },
            0x98 => { // TYA
                self.state.ac = self.state.yr;
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0x99 => { // STA abs,Y
                const destination_address = try self.getAbsoluteYAddress();
                try self.bus.write(destination_address, self.state.ac);
            },
            0x9A => { // TXS
                self.state.sp = self.state.xr;
            },
            0x9D => { // STA abs,X
                const destination_address = try self.getAbsoluteXAddress();
                try self.bus.write(destination_address, self.state.ac);
            },
            0xA0 => { // LDY #
                self.state.yr = try self.readNextByte();
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xA1 => { // LDA X,ind
                const source_address = try self.getZeroPageXIndirectAddress();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xA2 => { // LDX #
                self.state.xr = try self.readNextByte();
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xA4 => { // LDY zpg
                const source_address = try self.readNextByte();
                self.state.yr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xA5 => { // LDA zpg
                const source_address = try self.readNextByte();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xA6 => { // LDX zpg
                const source_address = try self.readNextByte();
                self.state.xr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xA8 => { // TAY
                self.state.yr = self.state.ac;
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xA9 => { // LDA #
                self.state.ac = try self.readNextByte();
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xAA => { // TAX
                self.state.xr = self.state.ac;
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xAC => { // LDY abs
                const source_address = try self.readAddressFromProgramCounter();
                self.state.yr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xAD => { // LDA abs
                const source_address = try self.readAddressFromProgramCounter();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xAE => { // LDX abs
                const source_address = try self.readAddressFromProgramCounter();
                self.state.xr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xB1 => { // LDA ind,Y
                const source_address = try self.getZeroPageYIndirectAddress();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xB4 => { // LDY zpg,X
                const source_address = try self.getZeroPageXAddress();
                self.state.yr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xB5 => { // LDA zpg,X
                const source_address = try self.getZeroPageXAddress();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xB6 => { // LDX zpg,Y
                const source_address = try self.getZeroPageYAddress();
                self.state.xr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xB9 => { // LDA abs,Y
                const source_address = try self.getAbsoluteYAddress();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xBA => { // TSX
                self.state.xr = self.state.sp;
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xBC => { // LDY abs,X
                const source_address = try self.getAbsoluteXAddress();
                self.state.yr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xBD => { // LDA abs,X
                const source_address = try self.getAbsoluteXAddress();
                self.state.ac = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.ac);
            },
            0xBE => { // LDX abs,Y
                const source_address = try self.getAbsoluteYAddress();
                self.state.xr = try self.bus.read(source_address);
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xC6 => { // DEC zpg
                const address = try self.readNextByte();
                try self.decrementValue(address);
            },
            0xC8 => { // INY
                self.state.yr = @addWithOverflow(self.state.yr, 1)[0];
                self.checkNegativeAndZeroFlags(self.state.yr);
            },
            0xCA => { // DEX
                self.state.xr = @subWithOverflow(self.state.xr, 1)[0];
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xCE => { // DEC abs
                const address = try self.readAddressFromProgramCounter();
                try self.decrementValue(address);
            },
            0xD6 => { // DEC zpg,X
                const address = try self.getZeroPageXAddress();
                try self.decrementValue(address);
            },
            0xDE => { // DEC abs,X
                const address = try self.getAbsoluteXAddress();
                try self.decrementValue(address);
            },
            0xE1 => { // SBC X,ind
                const operand_address = try self.getZeroPageXIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xE5 => { // SBC zpg
                const operand_address = try self.readNextByte();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xE6 => { // INC zpg
                const address = try self.readNextByte();
                try self.incrementValue(address);
            },
            0xE8 => { // INX
                self.state.xr = @addWithOverflow(self.state.xr, 1)[0];
                self.checkNegativeAndZeroFlags(self.state.xr);
            },
            0xE9 => { // SBC imm
                const operand = try self.readNextByte();
                self.subWithBorrow(operand);
            },
            0xED => { // SBC abs
                const operand_address = try self.readAddressFromProgramCounter();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xEE => { // INC abs
                const address = try self.readAddressFromProgramCounter();
                try self.incrementValue(address);
            },
            0xF1 => { // SBC ind,Y
                const operand_address = try self.getZeroPageYIndirectAddress();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xF5 => { // SBC zpg,X
                const operand_address = try self.getZeroPageXAddress();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xF6 => { // INC zpg,X
                const address = try self.getZeroPageXAddress();
                try self.incrementValue(address);
            },
            0xF9 => { // SBC abs,Y
                const operand_address = try self.getAbsoluteYAddress();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xFD => { // SBC abs,X
                const operand_address = try self.getAbsoluteXAddress();
                const operand = try self.bus.read(operand_address);
                self.subWithBorrow(operand);
            },
            0xFE => { // INC abs,X
                const address = try self.getAbsoluteXAddress();
                try self.incrementValue(address);
            },
            else => {
                return CpuError.illegal_opcode;
            },
        }
        self.bus.clock();
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
