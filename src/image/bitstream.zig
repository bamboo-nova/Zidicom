const std = @import("std");

/// Bitstream reader for JPEG data
/// Handles bit-level reading with byte stuffing removal
pub const BitReader = struct {
    data: []const u8,
    pos: usize, // Current byte position in data
    buffer: u32, // Bit buffer
    bits_left: u5, // Number of bits left in buffer (0-31)

    pub fn init(data: []const u8) BitReader {
        return .{
            .data = data,
            .pos = 0,
            .buffer = 0,
            .bits_left = 0,
        };
    }

    /// Fill the bit buffer with at least n bits
    fn fillBuffer(self: *BitReader, n: u5) !void {
        while (self.bits_left < n and self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            // Handle byte stuffing: 0xFF 0x00 -> 0xFF
            if (byte == 0xFF and self.pos < self.data.len) {
                const next = self.data[self.pos];
                if (next == 0x00) {
                    // Skip stuffed 0x00
                    self.pos += 1;
                } else if (next >= 0xD0 and next <= 0xD7) {
                    // RST marker, skip it
                    self.pos += 1;
                    continue;
                } else {
                    // Other marker, we should stop here
                    // Put back the FF and stop filling
                    self.pos -= 1;
                    return;
                }
            }

            self.buffer = (self.buffer << 8) | @as(u32, byte);
            self.bits_left += 8;
        }
    }

    /// Read n bits from the stream (1-16 bits)
    pub fn readBits(self: *BitReader, n: u5) !u16 {
        if (n == 0) return 0;
        if (n > 16) return error.InvalidBitCount;

        try self.fillBuffer(n);

        if (self.bits_left < n) {
            return error.EndOfStream;
        }

        const shift = self.bits_left - n;
        const mask = (@as(u32, 1) << n) - 1;
        const result = (self.buffer >> @intCast(shift)) & mask;

        self.bits_left -= n;
        self.buffer &= (@as(u32, 1) << @intCast(self.bits_left)) - 1;

        return @intCast(result);
    }

    /// Align to next byte boundary
    pub fn alignToByte(self: *BitReader) void {
        self.bits_left = 0;
        self.buffer = 0;
    }

    /// Peek at the next byte without advancing
    pub fn peekByte(self: *BitReader) ?u8 {
        if (self.pos >= self.data.len) return null;
        return self.data[self.pos];
    }

    /// Skip n bytes
    pub fn skipBytes(self: *BitReader, n: usize) !void {
        self.alignToByte();
        if (self.pos + n > self.data.len) {
            return error.EndOfStream;
        }
        self.pos += n;
    }

    /// Get current byte position
    pub fn getPos(self: *BitReader) usize {
        return self.pos;
    }
};

test "BitReader basic operations" {
    const data = [_]u8{ 0b10110011, 0b11001100 };
    var reader = BitReader.init(&data);

    // Read 4 bits: 1011
    const bits1 = try reader.readBits(4);
    try std.testing.expectEqual(@as(u16, 0b1011), bits1);

    // Read 8 bits: 0011 1100
    const bits2 = try reader.readBits(8);
    try std.testing.expectEqual(@as(u16, 0b00111100), bits2);
}

test "BitReader byte stuffing" {
    // 0xFF 0x00 should be treated as single 0xFF
    const data = [_]u8{ 0xFF, 0x00, 0xAB };
    var reader = BitReader.init(&data);

    // Read all bits as two bytes
    const byte1 = try reader.readBits(8);
    try std.testing.expectEqual(@as(u16, 0xFF), byte1);

    const byte2 = try reader.readBits(8);
    try std.testing.expectEqual(@as(u16, 0xAB), byte2);
}
