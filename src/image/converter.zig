const std = @import("std");
const stb = @import("../c/stb.zig");

/// Image format for output
pub const ImageFormat = enum {
    PNG,
    JPEG,
};

/// Conversion options
pub const ConversionOptions = struct {
    format: ImageFormat = .PNG,
    quality: u8 = 90, // For JPEG only (1-100)
    window_center: ?f32 = null,
    window_width: ?f32 = null,
};

/// Convert pixel data to image format
pub const Converter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Converter {
        return .{ .allocator = allocator };
    }

    /// Convert RGB data to PNG/JPEG
    pub fn convertToImage(
        self: Converter,
        rgb_data: []const u8,
        width: u16,
        height: u16,
        options: ConversionOptions,
    ) ![]u8 {
        const components: u8 = 3; // RGB

        return switch (options.format) {
            .PNG => try stb.writePngToMemory(
                self.allocator,
                rgb_data,
                width,
                height,
                components,
            ),
            .JPEG => try stb.writeJpegToMemory(
                self.allocator,
                rgb_data,
                width,
                height,
                components,
                options.quality,
            ),
        };
    }
};
