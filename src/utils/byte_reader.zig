const std = @import("std");
const errors = @import("errors.zig");

/// Binary data reader with endianness support
pub const ByteReader = struct {
    buffer: []const u8,
    pos: usize,
    is_little_endian: bool,

    /// Initialize a new ByteReader
    pub fn init(buffer: []const u8, is_little_endian: bool) ByteReader {
        return .{
            .buffer = buffer,
            .pos = 0,
            .is_little_endian = is_little_endian,
        };
    }

    /// Read a single byte
    pub fn readU8(self: *ByteReader) !u8 {
        if (self.pos >= self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        const value = self.buffer[self.pos];
        self.pos += 1;
        return value;
    }

    /// Read a 16-bit unsigned integer
    pub fn readU16(self: *ByteReader) !u16 {
        if (self.pos + 2 > self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        const bytes = self.buffer[self.pos .. self.pos + 2];
        self.pos += 2;

        if (self.is_little_endian) {
            return std.mem.readInt(u16, bytes[0..2], .little);
        } else {
            return std.mem.readInt(u16, bytes[0..2], .big);
        }
    }

    /// Read a 32-bit unsigned integer
    pub fn readU32(self: *ByteReader) !u32 {
        if (self.pos + 4 > self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        const bytes = self.buffer[self.pos .. self.pos + 4];
        self.pos += 4;

        if (self.is_little_endian) {
            return std.mem.readInt(u32, bytes[0..4], .little);
        } else {
            return std.mem.readInt(u32, bytes[0..4], .big);
        }
    }

    /// Read a slice of bytes
    pub fn readBytes(self: *ByteReader, len: usize) ![]const u8 {
        if (self.pos + len > self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        const slice = self.buffer[self.pos .. self.pos + len];
        self.pos += len;
        return slice;
    }

    /// Skip N bytes
    pub fn skip(self: *ByteReader, bytes: usize) !void {
        if (self.pos + bytes > self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        self.pos += bytes;
    }

    /// Check if at end of buffer
    pub fn atEnd(self: ByteReader) bool {
        return self.pos >= self.buffer.len;
    }

    /// Get current position
    pub fn getPos(self: ByteReader) usize {
        return self.pos;
    }

    /// Set position
    pub fn setPos(self: *ByteReader, pos: usize) !void {
        if (pos > self.buffer.len) {
            return errors.DicomError.UnexpectedEndOfData;
        }
        self.pos = pos;
    }

    /// Get remaining bytes
    pub fn remaining(self: ByteReader) usize {
        return self.buffer.len - self.pos;
    }
};

test "ByteReader readU8" {
    const data = [_]u8{ 0x12, 0x34, 0x56 };
    var reader = ByteReader.init(&data, true);

    try std.testing.expectEqual(@as(u8, 0x12), try reader.readU8());
    try std.testing.expectEqual(@as(u8, 0x34), try reader.readU8());
    try std.testing.expectEqual(@as(u8, 0x56), try reader.readU8());

    const result = reader.readU8();
    try std.testing.expectError(errors.DicomError.UnexpectedEndOfData, result);
}

test "ByteReader readU16 little endian" {
    const data = [_]u8{ 0x12, 0x34 };
    var reader = ByteReader.init(&data, true);

    try std.testing.expectEqual(@as(u16, 0x3412), try reader.readU16());
}

test "ByteReader readU16 big endian" {
    const data = [_]u8{ 0x12, 0x34 };
    var reader = ByteReader.init(&data, false);

    try std.testing.expectEqual(@as(u16, 0x1234), try reader.readU16());
}

test "ByteReader readU32" {
    const data = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
    var reader = ByteReader.init(&data, true);

    try std.testing.expectEqual(@as(u32, 0x78563412), try reader.readU32());
}

test "ByteReader readBytes" {
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    var reader = ByteReader.init(&data, true);

    const bytes = try reader.readBytes(3);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02, 0x03 }, bytes);
}

test "ByteReader skip" {
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    var reader = ByteReader.init(&data, true);

    try reader.skip(2);
    try std.testing.expectEqual(@as(u8, 0x03), try reader.readU8());
}

test "ByteReader atEnd" {
    const data = [_]u8{ 0x01, 0x02 };
    var reader = ByteReader.init(&data, true);

    try std.testing.expect(!reader.atEnd());
    _ = try reader.readU8();
    _ = try reader.readU8();
    try std.testing.expect(reader.atEnd());
}
