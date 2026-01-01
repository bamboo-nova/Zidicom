const std = @import("std");

/// Decoded image data
pub const DecodedImage = struct {
    data: []u8,
    width: u16,
    height: u16,
    channels: u8,
    bits_per_sample: u8 = 8, // Default to 8 bits per sample

    pub fn deinit(self: DecodedImage, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};
