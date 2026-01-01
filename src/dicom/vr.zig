const std = @import("std");

/// DICOM Value Representation
/// Defines the data type and format of a Data Element value
pub const VR = enum(u16) {
    // String types
    AE = 0x4145, // Application Entity
    AS = 0x4153, // Age String
    CS = 0x4353, // Code String
    DA = 0x4441, // Date
    DS = 0x4453, // Decimal String
    DT = 0x4454, // Date Time
    IS = 0x4953, // Integer String
    LO = 0x4C4F, // Long String
    LT = 0x4C54, // Long Text
    PN = 0x504E, // Person Name
    SH = 0x5348, // Short String
    ST = 0x5354, // Short Text
    TM = 0x544D, // Time
    UC = 0x5543, // Unlimited Characters
    UI = 0x5549, // Unique Identifier (UID)
    UR = 0x5552, // URI/URL
    UT = 0x5554, // Unlimited Text

    // Binary types
    AT = 0x4154, // Attribute Tag
    FL = 0x464C, // Floating Point Single
    FD = 0x4644, // Floating Point Double
    OB = 0x4F42, // Other Byte
    OD = 0x4F44, // Other Double
    OF = 0x4F46, // Other Float
    OL = 0x4F4C, // Other Long
    OV = 0x4F56, // Other 64-bit Very Long
    OW = 0x4F57, // Other Word
    SL = 0x534C, // Signed Long
    SQ = 0x5351, // Sequence of Items
    SS = 0x5353, // Signed Short
    SV = 0x5356, // Signed 64-bit Very Long
    UL = 0x554C, // Unsigned Long
    UN = 0x554E, // Unknown
    US = 0x5553, // Unsigned Short
    UV = 0x5556, // Unsigned 64-bit Very Long

    /// Parse VR from two-character string
    pub fn fromString(str: []const u8) !VR {
        if (str.len != 2) {
            return error.InvalidVR;
        }

        // Validate that both bytes are printable ASCII characters
        if (str[0] < 0x20 or str[0] > 0x7E or str[1] < 0x20 or str[1] > 0x7E) {
            return error.InvalidVR;
        }

        const value = (@as(u16, str[0]) << 8) | @as(u16, str[1]);

        // Validate that the value corresponds to a known VR
        // This prevents invalid enum values
        return switch (value) {
            @intFromEnum(VR.AE), @intFromEnum(VR.AS), @intFromEnum(VR.AT), @intFromEnum(VR.CS),
            @intFromEnum(VR.DA), @intFromEnum(VR.DS), @intFromEnum(VR.DT), @intFromEnum(VR.FL),
            @intFromEnum(VR.FD), @intFromEnum(VR.IS), @intFromEnum(VR.LO), @intFromEnum(VR.LT),
            @intFromEnum(VR.OB), @intFromEnum(VR.OD), @intFromEnum(VR.OF), @intFromEnum(VR.OL),
            @intFromEnum(VR.OV), @intFromEnum(VR.OW), @intFromEnum(VR.PN), @intFromEnum(VR.SH),
            @intFromEnum(VR.SL), @intFromEnum(VR.SQ), @intFromEnum(VR.SS), @intFromEnum(VR.ST),
            @intFromEnum(VR.SV), @intFromEnum(VR.TM), @intFromEnum(VR.UC), @intFromEnum(VR.UI),
            @intFromEnum(VR.UL), @intFromEnum(VR.UN), @intFromEnum(VR.UR), @intFromEnum(VR.US),
            @intFromEnum(VR.UT), @intFromEnum(VR.UV) => @enumFromInt(value),
            else => error.InvalidVR,
        };
    }

    /// Convert VR to two-character string
    pub fn toString(self: VR) [2]u8 {
        const value = @intFromEnum(self);
        return .{
            @truncate(value >> 8),
            @truncate(value & 0xFF),
        };
    }

    /// Check if this VR represents string data
    pub fn isString(self: VR) bool {
        return switch (self) {
            .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT => true,
            else => false,
        };
    }

    /// Check if this VR has explicit 32-bit length field
    pub fn hasExplicitLength(self: VR) bool {
        return switch (self) {
            .OB, .OD, .OF, .OL, .OV, .OW, .SQ, .UC, .UN, .UR, .UT => true,
            else => false,
        };
    }

    /// Get maximum length for this VR (if defined)
    pub fn maxLength(self: VR) ?u32 {
        return switch (self) {
            .AE => 16,
            .AS => 4,
            .AT => 4,
            .CS => 16,
            .DA => 8,
            .DS => 16,
            .DT => 26,
            .FL => 4,
            .FD => 8,
            .IS => 12,
            .LO => 64,
            .PN => 64,
            .SH => 16,
            .SL => 4,
            .SS => 2,
            .TM => 14,
            .UI => 64,
            .UL => 4,
            .US => 2,
            else => null, // Variable or unlimited length
        };
    }

    /// Format VR for printing
    pub fn format(
        self: VR,
        writer: anytype,
    ) !void {
        try writer.writeAll(&self.toString());
    }

    /// Infer VR from tag (for Implicit VR)
    pub fn inferFromTag(tag: anytype) VR {
        // This is a simplified version
        // In a full implementation, you would have a lookup table
        // For now, return UN (Unknown) for most tags
        _ = tag;
        return VR.UN;
    }
};

test "VR fromString" {
    try std.testing.expectEqual(VR.AE, try VR.fromString("AE"));
    try std.testing.expectEqual(VR.UI, try VR.fromString("UI"));
    try std.testing.expectEqual(VR.OB, try VR.fromString("OB"));
    try std.testing.expectEqual(VR.SQ, try VR.fromString("SQ"));
}

test "VR toString" {
    try std.testing.expectEqualSlices(u8, "AE", &VR.AE.toString());
    try std.testing.expectEqualSlices(u8, "UI", &VR.UI.toString());
    try std.testing.expectEqualSlices(u8, "OB", &VR.OB.toString());
}

test "VR isString" {
    try std.testing.expect(VR.AE.isString());
    try std.testing.expect(VR.UI.isString());
    try std.testing.expect(!VR.OB.isString());
    try std.testing.expect(!VR.SQ.isString());
}

test "VR hasExplicitLength" {
    try std.testing.expect(VR.OB.hasExplicitLength());
    try std.testing.expect(VR.SQ.hasExplicitLength());
    try std.testing.expect(!VR.AE.hasExplicitLength());
    try std.testing.expect(!VR.UI.hasExplicitLength());
}
