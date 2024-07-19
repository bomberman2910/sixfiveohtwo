const std = @import("std");

pub const BusDevice = struct {
    start: u16,
    length: u17 = 0,
    data: []u8 = undefined,
    clock: ?*const fn (self: *BusDevice) void,
    isReadOnly: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, start: u16, clockAction: ?*const fn (self: *BusDevice) void, isReadOnly: bool) BusDevice {
        return BusDevice{ .start = start, .clock = clockAction, .isReadOnly = isReadOnly, .allocator = allocator };
    }

    pub fn setMemSize(self: *BusDevice, size: u17) !void {
        const end: u32 = @as(u32, self.start) + size - 1;
        if (end > std.math.maxInt(u16)) return BusDeviceError.DeviceTooLong;
        self.length = size;
        self.data = try self.allocator.alloc(u8, size);
        @memset(self.data, 0);
    }

    pub fn deinit(self: *const BusDevice) void {
        self.allocator.free(self.data);
    }
};

pub const BusDeviceError = error{DeviceTooLong};

test "noLeaksInBusDevice" {
    const dummyClockActionCarrier = struct {
        fn action(device: *BusDevice) void {
            _ = device;
        }
    };
    var device = BusDevice.init(std.testing.allocator, 0x200, dummyClockActionCarrier.action, false);
    try device.setMemSize(0x10);
    defer device.deinit();
}
