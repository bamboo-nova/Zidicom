const std = @import("std");

/// DICOM Transfer Syntax
pub const TransferSyntax = enum {
    ImplicitVRLittleEndian,
    ExplicitVRLittleEndian,
    ExplicitVRBigEndian,
    JPEGBaseline,
    JPEGLossless,
    JPEG2000Lossless,
    JPEG2000,
    RLELossless,

    /// Map from Transfer Syntax UID to enum
    pub fn fromUID(uid: []const u8) !TransferSyntax {
        // Remove trailing spaces and null bytes
        const trimmed = std.mem.trim(u8, uid, &[_]u8{ ' ', 0 });

        if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2")) {
            return .ImplicitVRLittleEndian;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.1")) {
            return .ExplicitVRLittleEndian;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.2")) {
            return .ExplicitVRBigEndian;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.4.50")) {
            return .JPEGBaseline;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.4.70")) {
            return .JPEGLossless;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.4.90")) {
            return .JPEG2000Lossless;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.4.91")) {
            return .JPEG2000;
        } else if (std.mem.eql(u8, trimmed, "1.2.840.10008.1.2.5")) {
            return .RLELossless;
        } else {
            return error.UnsupportedTransferSyntax;
        }
    }

    /// Get UID string for this transfer syntax
    pub fn toUID(self: TransferSyntax) []const u8 {
        return switch (self) {
            .ImplicitVRLittleEndian => "1.2.840.10008.1.2",
            .ExplicitVRLittleEndian => "1.2.840.10008.1.2.1",
            .ExplicitVRBigEndian => "1.2.840.10008.1.2.2",
            .JPEGBaseline => "1.2.840.10008.1.2.4.50",
            .JPEGLossless => "1.2.840.10008.1.2.4.70",
            .JPEG2000Lossless => "1.2.840.10008.1.2.4.90",
            .JPEG2000 => "1.2.840.10008.1.2.4.91",
            .RLELossless => "1.2.840.10008.1.2.5",
        };
    }

    /// Check if this transfer syntax uses explicit VR
    pub fn isExplicitVR(self: TransferSyntax) bool {
        return switch (self) {
            .ImplicitVRLittleEndian => false,
            else => true,
        };
    }

    /// Check if this transfer syntax uses little endian byte order
    pub fn isLittleEndian(self: TransferSyntax) bool {
        return switch (self) {
            .ExplicitVRBigEndian => false,
            else => true,
        };
    }

    /// Check if pixel data is encapsulated (compressed)
    pub fn isEncapsulated(self: TransferSyntax) bool {
        return switch (self) {
            .ImplicitVRLittleEndian, .ExplicitVRLittleEndian, .ExplicitVRBigEndian => false,
            .JPEGBaseline, .JPEGLossless, .JPEG2000Lossless, .JPEG2000, .RLELossless => true,
        };
    }

    /// Get human-readable name
    pub fn getName(self: TransferSyntax) []const u8 {
        return switch (self) {
            .ImplicitVRLittleEndian => "Implicit VR Little Endian",
            .ExplicitVRLittleEndian => "Explicit VR Little Endian",
            .ExplicitVRBigEndian => "Explicit VR Big Endian",
            .JPEGBaseline => "JPEG Baseline (Process 1)",
            .JPEGLossless => "JPEG Lossless",
            .JPEG2000Lossless => "JPEG 2000 Lossless",
            .JPEG2000 => "JPEG 2000",
            .RLELossless => "RLE Lossless",
        };
    }
};

test "TransferSyntax fromUID" {
    const implicit = try TransferSyntax.fromUID("1.2.840.10008.1.2");
    try std.testing.expectEqual(TransferSyntax.ImplicitVRLittleEndian, implicit);

    const explicit = try TransferSyntax.fromUID("1.2.840.10008.1.2.1");
    try std.testing.expectEqual(TransferSyntax.ExplicitVRLittleEndian, explicit);

    const jpeg_baseline = try TransferSyntax.fromUID("1.2.840.10008.1.2.4.50");
    try std.testing.expectEqual(TransferSyntax.JPEGBaseline, jpeg_baseline);

    // Test with trailing spaces
    const implicit_padded = try TransferSyntax.fromUID("1.2.840.10008.1.2   ");
    try std.testing.expectEqual(TransferSyntax.ImplicitVRLittleEndian, implicit_padded);
}

test "TransferSyntax properties" {
    try std.testing.expect(!TransferSyntax.ImplicitVRLittleEndian.isExplicitVR());
    try std.testing.expect(TransferSyntax.ExplicitVRLittleEndian.isExplicitVR());

    try std.testing.expect(TransferSyntax.ExplicitVRLittleEndian.isLittleEndian());
    try std.testing.expect(!TransferSyntax.ExplicitVRBigEndian.isLittleEndian());

    try std.testing.expect(!TransferSyntax.ExplicitVRLittleEndian.isEncapsulated());
    try std.testing.expect(TransferSyntax.JPEGBaseline.isEncapsulated());
    try std.testing.expect(TransferSyntax.JPEGLossless.isEncapsulated());
}
