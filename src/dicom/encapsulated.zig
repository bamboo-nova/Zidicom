const std = @import("std");
const errors = @import("../utils/errors.zig");

/// Parse encapsulated pixel data (JPEG, JPEG2000, etc.)
pub const EncapsulatedPixelData = struct {
    /// Extract JPEG frames from encapsulated pixel data
    pub fn extractJPEGFrames(data: []const u8, allocator: std.mem.Allocator) !std.ArrayListUnmanaged([]const u8) {
        var frames: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer frames.deinit(allocator);

        var pos: usize = 0;

        // Skip offset table if present
        if (pos + 8 <= data.len) {
            const tag_group = std.mem.readInt(u16, data[pos..][0..2], .little);
            const tag_elem = std.mem.readInt(u16, data[pos + 2..][0..4][0..2], .little);

            // Check for Item tag (FFFE,E000)
            if (tag_group == 0xFFFE and tag_elem == 0xE000) {
                const item_length = std.mem.readInt(u32, data[pos + 4..][0..4], .little);
                pos += 8; // Skip tag and length

                // If this is the offset table, skip it
                // Offset table has even number of bytes and contains offsets
                if (item_length > 0 and item_length % 4 == 0) {
                    pos += item_length; // Skip offset table
                }
            }
        }

        // Extract JPEG frames
        while (pos + 8 <= data.len) {
            const tag_group = std.mem.readInt(u16, data[pos..][0..2], .little);
            const tag_elem = std.mem.readInt(u16, data[pos + 2..][0..4][0..2], .little);

            if (tag_group == 0xFFFE and tag_elem == 0xE000) {
                // Item tag
                const item_length = std.mem.readInt(u32, data[pos + 4..][0..4], .little);
                pos += 8;

                if (item_length == 0 or pos + item_length > data.len) {
                    break;
                }

                // Add this frame
                const frame_data = data[pos .. pos + item_length];
                try frames.append(allocator, frame_data);

                pos += item_length;
            } else if (tag_group == 0xFFFE and tag_elem == 0xE0DD) {
                // Sequence Delimiter Item
                break;
            } else {
                // Unknown tag, stop parsing
                break;
            }
        }

        return frames;
    }
};

test "EncapsulatedPixelData extraction" {
    const allocator = std.testing.allocator;

    // Create a simple encapsulated format with one JPEG frame
    var buffer: [100]u8 = undefined;
    var pos: usize = 0;

    // Offset table (empty)
    std.mem.writeInt(u16, buffer[pos..][0..2], 0xFFFE, .little);
    std.mem.writeInt(u16, buffer[pos + 2..][0..2], 0xE000, .little);
    std.mem.writeInt(u32, buffer[pos + 4..][0..4], 0, .little);
    pos += 8;

    // JPEG frame
    std.mem.writeInt(u16, buffer[pos..][0..2], 0xFFFE, .little);
    std.mem.writeInt(u16, buffer[pos + 2..][0..2], 0xE000, .little);
    std.mem.writeInt(u32, buffer[pos + 4..][0..4], 10, .little);
    pos += 8;
    @memcpy(buffer[pos .. pos + 10], "JPEG_DATA\x00");
    pos += 10;

    // Sequence delimiter
    std.mem.writeInt(u16, buffer[pos..][0..2], 0xFFFE, .little);
    std.mem.writeInt(u16, buffer[pos + 2..][0..2], 0xE0DD, .little);
    pos += 4;

    var frames = try EncapsulatedPixelData.extractJPEGFrames(buffer[0..pos], allocator);
    defer frames.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), frames.items.len);
    try std.testing.expectEqualStrings("JPEG_DATA\x00", frames.items[0]);
}
