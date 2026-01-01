const std = @import("std");

/// JPEG marker codes
pub const Marker = enum(u8) {
    // Start of Frame markers (non-differential, Huffman coding)
    SOF0 = 0xC0, // Baseline DCT
    SOF1 = 0xC1, // Extended sequential DCT
    SOF2 = 0xC2, // Progressive DCT
    SOF3 = 0xC3, // Lossless (sequential)

    // Define Huffman Table
    DHT = 0xC4,

    // Start of Frame markers (differential, Huffman coding)
    SOF5 = 0xC5, // Differential sequential DCT
    SOF6 = 0xC6, // Differential progressive DCT
    SOF7 = 0xC7, // Differential lossless

    // Start of Frame markers (non-differential, arithmetic coding)
    JPG = 0xC8, // Reserved for JPEG extensions
    SOF9 = 0xC9, // Extended sequential DCT (arithmetic)
    SOF10 = 0xCA, // Progressive DCT (arithmetic)
    SOF11 = 0xCB, // Lossless (arithmetic)

    // Define Arithmetic Coding
    DAC = 0xCC,

    // Start of Frame markers (differential, arithmetic coding)
    SOF13 = 0xCD, // Differential sequential DCT (arithmetic)
    SOF14 = 0xCE, // Differential progressive DCT (arithmetic)
    SOF15 = 0xCF, // Differential lossless (arithmetic)

    // Restart interval markers
    RST0 = 0xD0,
    RST1 = 0xD1,
    RST2 = 0xD2,
    RST3 = 0xD3,
    RST4 = 0xD4,
    RST5 = 0xD5,
    RST6 = 0xD6,
    RST7 = 0xD7,

    // Other markers
    SOI = 0xD8, // Start of Image
    EOI = 0xD9, // End of Image
    SOS = 0xDA, // Start of Scan
    DQT = 0xDB, // Define Quantization Table
    DNL = 0xDC, // Define Number of Lines
    DRI = 0xDD, // Define Restart Interval
    DHP = 0xDE, // Define Hierarchical Progression
    EXP = 0xDF, // Expand Reference Component

    // Application markers
    APP0 = 0xE0,
    APP1 = 0xE1,
    APP2 = 0xE2,
    APP3 = 0xE3,
    APP4 = 0xE4,
    APP5 = 0xE5,
    APP6 = 0xE6,
    APP7 = 0xE7,
    APP8 = 0xE8,
    APP9 = 0xE9,
    APP10 = 0xEA,
    APP11 = 0xEB,
    APP12 = 0xEC,
    APP13 = 0xED,
    APP14 = 0xEE,
    APP15 = 0xEF,

    // Extension markers
    COM = 0xFE, // Comment

    _,

    pub fn isSOF(marker: u8) bool {
        return switch (marker) {
            0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
            0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF => true,
            else => false,
        };
    }

    pub fn isLossless(marker: u8) bool {
        return marker == 0xC3 or marker == 0xC7 or marker == 0xCB or marker == 0xCF;
    }

    pub fn usesArithmeticCoding(marker: u8) bool {
        return switch (marker) {
            0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF => true,
            else => false,
        };
    }
};

/// Read a JPEG marker from data
pub fn readMarker(data: []const u8, pos: *usize) !u8 {
    if (pos.* + 1 >= data.len) {
        return error.UnexpectedEndOfData;
    }

    if (data[pos.*] != 0xFF) {
        return error.InvalidMarker;
    }

    pos.* += 1;
    const marker = data[pos.*];
    pos.* += 1;

    return marker;
}

/// Read marker segment length (excluding marker itself)
pub fn readSegmentLength(data: []const u8, pos: *usize) !u16 {
    if (pos.* + 1 >= data.len) {
        return error.UnexpectedEndOfData;
    }

    const length = std.mem.readInt(u16, data[pos.*..][0..2], .big);
    pos.* += 2;

    if (length < 2) {
        return error.InvalidSegmentLength;
    }

    return length;
}

test "Marker identification" {
    try std.testing.expect(Marker.isSOF(0xC3));
    try std.testing.expect(Marker.isLossless(0xC3));
    try std.testing.expect(!Marker.usesArithmeticCoding(0xC3));

    try std.testing.expect(Marker.isLossless(0xCB));
    try std.testing.expect(Marker.usesArithmeticCoding(0xCB));
}
