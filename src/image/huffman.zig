const std = @import("std");
const BitReader = @import("bitstream.zig").BitReader;

/// Huffman table for JPEG decoding
pub const HuffmanTable = struct {
    /// Number of codes of each length (1-16 bits)
    bits: [17]u8,
    /// Huffman values
    huffval: [256]u8,
    /// Lookup tables for fast decoding
    lookup: [65536]i16, // -1 means not found, otherwise index into huffval
    max_code: [17]i32, // Maximum code of each length
    min_code: [17]i32, // Minimum code of each length
    val_offset: [17]i32, // Offset into huffval for codes of this length

    pub fn init() HuffmanTable {
        var table: HuffmanTable = undefined;
        @memset(&table.bits, 0);
        @memset(&table.huffval, 0);
        @memset(&table.lookup, -1);
        @memset(&table.max_code, -1);
        @memset(&table.min_code, -1);
        @memset(&table.val_offset, 0);
        return table;
    }

    /// Build the decoding tables from bits and huffval
    pub fn build(self: *HuffmanTable) !void {
        var code: i32 = 0;
        var val_index: usize = 0;

        // Generate code tables
        for (1..17) |i| {
            if (self.bits[i] != 0) {
                self.min_code[i] = code;
                self.val_offset[i] = @as(i32, @intCast(val_index)) - code;
                val_index += self.bits[i];
                code += self.bits[i];
                self.max_code[i] = code - 1;
            } else {
                self.max_code[i] = -1;
            }
            code <<= 1;
        }

        // Build fast lookup table for codes up to 16 bits
        val_index = 0;
        for (1..17) |length| {
            if (self.bits[length] == 0) continue;

            for (0..self.bits[length]) |_| {
                if (val_index >= 256) return error.InvalidHuffmanTable;

                const value = self.huffval[val_index];
                val_index += 1;

                // For this value, calculate all possible 16-bit codes
                // by padding with zeros on the right
                const base_code = @as(u32, @intCast(self.min_code[length] +
                    (@as(i32, @intCast(val_index)) - @as(i32, @intCast(self.val_offset[length])) - 1)));

                const shift_amount = 16 - length;
                const lookup_start = base_code << @intCast(shift_amount);
                const lookup_count: u32 = @as(u32, 1) << @intCast(shift_amount);

                var j: u32 = 0;
                while (j < lookup_count) : (j += 1) {
                    const lookup_index = lookup_start + j;
                    if (lookup_index < 65536) {
                        // Store value with length encoded in high byte
                        self.lookup[lookup_index] = (@as(i16, @intCast(length)) << 8) | @as(i16, @intCast(value));
                    }
                }
            }
        }
    }

    /// Decode next Huffman symbol from bit reader
    pub fn decode(self: *HuffmanTable, reader: *BitReader) !u8 {
        // Use slow path for now (bit-by-bit decoding)
        // Fast lookup requires ability to put bits back, which is complex
        return self.decodeSlow(reader);
    }

    fn decodeSlow(self: *HuffmanTable, reader: *BitReader) !u8 {
        var code: i32 = 0;

        for (1..17) |length| {
            const bit = try reader.readBits(1);
            code = (code << 1) | @as(i32, @intCast(bit));

            if (code <= self.max_code[length] and self.max_code[length] >= 0) {
                const index: usize = @intCast(code + self.val_offset[length]);
                if (index >= 256) return error.InvalidHuffmanCode;
                return self.huffval[index];
            }
        }

        return error.InvalidHuffmanCode;
    }
};

/// Decode a signed value from Huffman code
/// ssss is the category (number of bits for the value)
pub fn decodeValue(reader: *BitReader, ssss: u8) !i32 {
    if (ssss == 0) return 0;
    if (ssss > 16) return error.InvalidCategory;

    const bits = try reader.readBits(@intCast(ssss));
    const threshold: u16 = @as(u16, 1) << @intCast(ssss - 1);

    if (bits >= threshold) {
        // Positive value
        return @as(i32, @intCast(bits));
    } else {
        // Negative value: bits - (2^ssss - 1)
        const max_val: i32 = (@as(i32, 1) << @intCast(ssss)) - 1;
        return @as(i32, @intCast(bits)) - max_val;
    }
}

test "Huffman table build" {
    var table = HuffmanTable.init();

    // Simple Huffman table:
    // 0 -> 00 (2 bits)
    // 1 -> 01 (2 bits)
    table.bits[1] = 0;
    table.bits[2] = 2;
    table.huffval[0] = 0;
    table.huffval[1] = 1;

    try table.build();

    try std.testing.expect(table.min_code[2] == 0);
    try std.testing.expect(table.max_code[2] == 1);
}

test "decodeValue" {
    const data = [_]u8{0b10110000}; // Contains: 101 (5 in 3 bits), 10000...
    var reader = BitReader.init(&data);

    // Read category 3 value: 101 = 5
    const value = try decodeValue(&reader, 3);
    try std.testing.expectEqual(@as(i32, 5), value);
}
