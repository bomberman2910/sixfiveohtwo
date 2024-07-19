const std = @import("std");
const processor = @import("./cpu.zig");
const busdevice = @import("./busdevice.zig");

const BusDevice = busdevice.BusDevice;

pub const BusError = error{ NoDeviceAtAddress, CannotWriteToReadOnlyDevice };

pub const Bus = struct {
    devices: std.ArrayList(BusDevice),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Bus {
        return Bus{ .devices = std.ArrayList(BusDevice).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *Bus) void {
        for (self.devices.items) |*device| {
            device.*.deinit();
        }
        self.devices.deinit();
    }

    pub fn addDevice(self: *Bus, start: u16, length: u17, clockAction: ?*const fn (self: *BusDevice) void, isReadOnly: bool) !void {
        var device = BusDevice.init(self.allocator, start, clockAction, isReadOnly);
        try device.setMemSize(length);
        try self.devices.append(device);
    }

    pub fn read(self: *Bus, address: u16) !u8 {
        for (self.devices.items) |device| {
            const lastAddress = device.start + (device.length - 1);
            if (device.start <= address and lastAddress >= address) {
                const offset = address - device.start;
                return device.data[offset];
            }
        }

        return BusError.NoDeviceAtAddress;
    }

    pub fn write(self: *Bus, address: u16, data: u8) !void {
        for (self.devices.items) |device| {
            const lastAddress = device.start + (device.length - 1);
            if (device.start <= address and lastAddress >= address) {
                if (device.isReadOnly) {
                    return BusError.CannotWriteToReadOnlyDevice;
                }
                const offset = address - device.start;
                device.data[offset] = data;
                return;
            }
        }

        return BusError.NoDeviceAtAddress;
    }

    pub fn clock(self: *Bus) void {
        for (self.devices.items) |*device| {
            if (device.clock) |clockAction| {
                clockAction(device);
            }
        }
    }
};

const testingAllocator = std.testing.allocator;

test "initAndDeinitBus" {
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
}

test "initAndDeinitBusAndSingleDevice" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);
    defer bus.deinit();
}

test "addDeviceToEndOfAddressSpace" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    try bus.addDevice(0xFFFA, 6, dummyClockActionCarrier.action, true);
    defer bus.deinit();
}

test "writeToBus_readWriteDevice_middleAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    try bus.write(0x208, 0xFF);

    try std.testing.expectEqual(0xFF, bus.devices.items[0].data[0x8]);
}

test "writeToBus_readWriteDevice_firstAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    try bus.write(0x200, 0xFF);

    try std.testing.expectEqual(0xFF, bus.devices.items[0].data[0x0]);
}

test "writeToBus_readWriteDevice_lastAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    try bus.write(0x20F, 0xFF);

    try std.testing.expectEqual(0xFF, bus.devices.items[0].data[0xF]);
}

test "writeToBus_readOnlyDevice" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, true);

    bus.write(0x208, 0xFF) catch |err| {
        try std.testing.expectEqual(BusError.CannotWriteToReadOnlyDevice, err);
        return;
    };

    try std.testing.expect(false);
}

test "readFromBus_readWriteDevice_middleAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    bus.devices.items[0].data[0x8] = 0xFF;

    const readByte = try bus.read(0x208);

    try std.testing.expectEqual(0xFF, readByte);
}

test "readFromBus_readWriteDevice_firstAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    bus.devices.items[0].data[0x0] = 0xFF;

    const readByte = try bus.read(0x200);

    try std.testing.expectEqual(0xFF, readByte);
}

test "readFromBus_readWriteDevice_lastAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, false);

    bus.devices.items[0].data[0xF] = 0xFF;

    const readByte = try bus.read(0x20F);

    try std.testing.expectEqual(0xFF, readByte);
}

test "readFromBus_readOnlyDevice_middleAddress" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.action, true);

    bus.devices.items[0].data[0x8] = 0xFF;

    const readByte = try bus.read(0x208);

    try std.testing.expectEqual(0xFF, readByte);
}

test "executeClockAction" {
    const dummyClockActionCarrier = struct {
        fn deviceClockAction(device: *BusDevice) void {
            device.data[0x0] = 0xFF;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.deviceClockAction, true);

    const readByteBefore = try bus.read(0x200);
    bus.clock();
    const readByteAfter = try bus.read(0x200);

    try std.testing.expectEqual(0x00, readByteBefore);
    try std.testing.expectEqual(0xFF, readByteAfter);
}

test "executeClockWithUndefinedActions" {
    const dummyClockActionCarrier = struct {
        fn deviceClockAction(device: *BusDevice) void {
            device.data[0x0] = 0xFF;
        }
    };
    var bus = Bus.init(testingAllocator);
    defer bus.deinit();
    try bus.addDevice(0x200, 0x10, dummyClockActionCarrier.deviceClockAction, true);
    try bus.addDevice(0x200, 0x10, null, true);
    bus.clock();
}
