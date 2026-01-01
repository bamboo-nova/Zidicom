const std = @import("std");

/// Global general purpose allocator for WASM
var gpa_instance: std.heap.GeneralPurposeAllocator(.{}) = .{};

/// Optional arena allocator for per-request temporary allocations
var arena_instance: ?std.heap.ArenaAllocator = null;

/// Get the global general purpose allocator
pub fn getGlobalAllocator() std.mem.Allocator {
    return gpa_instance.allocator();
}

/// Get or create the arena allocator
pub fn getArenaAllocator() std.mem.Allocator {
    if (arena_instance == null) {
        arena_instance = std.heap.ArenaAllocator.init(getGlobalAllocator());
    }
    return arena_instance.?.allocator();
}

/// Reset the arena allocator, freeing all memory but retaining capacity
pub fn resetArena() void {
    if (arena_instance) |*arena| {
        _ = arena.reset(.retain_capacity);
    }
}

/// Deinitialize the arena allocator
pub fn deinitArena() void {
    if (arena_instance) |*arena| {
        arena.deinit();
        arena_instance = null;
    }
}

/// Deinitialize all allocators (for cleanup)
pub fn deinitAll() void {
    deinitArena();
    _ = gpa_instance.deinit();
}

test "global allocator" {
    const allocator = getGlobalAllocator();
    const buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);

    try std.testing.expect(buffer.len == 100);
}

test "arena allocator" {
    const arena_alloc = getArenaAllocator();

    const buffer1 = try arena_alloc.alloc(u8, 50);
    const buffer2 = try arena_alloc.alloc(u8, 100);

    try std.testing.expect(buffer1.len == 50);
    try std.testing.expect(buffer2.len == 100);

    // Reset arena - all allocations are freed
    resetArena();

    // Can allocate again after reset
    const buffer3 = try arena_alloc.alloc(u8, 75);
    try std.testing.expect(buffer3.len == 75);

    // Clean up
    deinitArena();
}
