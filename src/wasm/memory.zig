const std = @import("std");
const allocator_mod = @import("allocator.zig");

/// WASM memory management with allocation tracking
pub const WasmMemory = struct {
    allocator: std.mem.Allocator,
    allocations: std.ArrayList(Allocation),

    const Allocation = struct {
        ptr: []u8,
    };

    pub fn init(allocator: std.mem.Allocator) WasmMemory {
        return .{
            .allocator = allocator,
            .allocations = .{},
        };
    }

    pub fn deinit(self: *WasmMemory) void {
        for (self.allocations.items) |a| {
            self.allocator.free(a.ptr);
        }
        self.allocations.clearAndFree(self.allocator);
    }

    pub fn alloc(self: *WasmMemory, size: usize) !usize {
        const slice = try self.allocator.alloc(u8, size);
        try self.allocations.append(self.allocator, .{ .ptr = slice });
        return @intFromPtr(slice.ptr);
    }

    pub fn free(self: *WasmMemory, ptr: usize, size: usize) void {
        const slice = @as([*]u8, @ptrFromInt(ptr))[0..size];

        for (self.allocations.items, 0..) |a, i| {
            if (a.ptr.ptr == slice.ptr) {
                _ = self.allocations.swapRemove(i);
                break;
            }
        }

        self.allocator.free(slice);
    }

    pub fn getAllocationCount(self: WasmMemory) usize {
        return self.allocations.items.len;
    }

    pub fn getTotalAllocated(self: WasmMemory) usize {
        var total: usize = 0;
        for (self.allocations.items) |a| {
            total += a.ptr.len;
        }
        return total;
    }

    /// Get a slice from a WASM pointer
    pub fn getSlice(self: WasmMemory, ptr: usize, len: usize) ![]u8 {
        _ = self;
        const slice_ptr = @as([*]u8, @ptrFromInt(ptr));
        return slice_ptr[0..len];
    }

    /// Get a const slice from a WASM pointer
    pub fn getConstSlice(self: WasmMemory, ptr: usize, len: usize) ![]const u8 {
        _ = self;
        const slice_ptr = @as([*]const u8, @ptrFromInt(ptr));
        return slice_ptr[0..len];
    }
};

test "WasmMemory alloc and free" {
    const allocator = std.testing.allocator;
    var memory = WasmMemory.init(allocator);
    defer memory.deinit();

    const ptr1 = try memory.alloc(100);
    const ptr2 = try memory.alloc(200);

    try std.testing.expect(ptr1 != 0);
    try std.testing.expect(ptr2 != 0);
    try std.testing.expect(ptr1 != ptr2);
    try std.testing.expectEqual(@as(usize, 2), memory.getAllocationCount());
    try std.testing.expectEqual(@as(usize, 300), memory.getTotalAllocated());

    memory.free(ptr1, 100);
    try std.testing.expectEqual(@as(usize, 1), memory.getAllocationCount());
    try std.testing.expectEqual(@as(usize, 200), memory.getTotalAllocated());
}
