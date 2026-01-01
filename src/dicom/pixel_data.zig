const std = @import("std");
const builtin = @import("builtin");
const Dataset = @import("parser.zig").Dataset;
const Tag = @import("data_element.zig").Tag;
const TransferSyntax = @import("transfer_syntax.zig").TransferSyntax;
const EncapsulatedPixelData = @import("encapsulated.zig").EncapsulatedPixelData;
const errors = @import("../utils/errors.zig");

// Only import JPEG-related modules for non-WASM targets
const is_wasm = builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64;
const stb = if (is_wasm) void else @import("../c/stb.zig");
const jpeg_lossless = if (is_wasm) void else @import("../image/jpeg_lossless.zig");

/// Pixel data extraction and processing
pub const PixelData = struct {
    data: []const u8,
    rows: u16,
    columns: u16,
    bits_allocated: u16,
    bits_stored: u16,
    samples_per_pixel: u16,
    photometric_interpretation: []const u8,
    owns_data: bool, // Whether this struct owns the data and should free it

    /// Extract pixel data from dataset
    pub fn fromDataset(dataset: Dataset, transfer_syntax: TransferSyntax, allocator: std.mem.Allocator) !PixelData {
        const pixel_elem = dataset.findElement(Tag.PixelData) orelse return errors.DicomError.PixelDataNotFound;
        const pixel_data = try pixel_elem.getValue(dataset.buffer);

        const rows = try dataset.getValueAsU16(Tag.Rows, true) orelse return errors.DicomError.InvalidPixelData;
        const columns = try dataset.getValueAsU16(Tag.Columns, true) orelse return errors.DicomError.InvalidPixelData;
        var bits_allocated = try dataset.getValueAsU16(Tag.BitsAllocated, true) orelse 16;
        var bits_stored = try dataset.getValueAsU16(Tag.BitsStored, true) orelse bits_allocated;
        var samples_per_pixel = try dataset.getValueAsU16(Tag.SamplesPerPixel, true) orelse 1;
        const photometric = try dataset.getValueAsString(Tag.PhotometricInterpretation, allocator) orelse try allocator.dupe(u8, "MONOCHROME2");
        errdefer allocator.free(photometric);

        var owns_data = false;
        var decoded_data: []const u8 = pixel_data;

        // If encapsulated (compressed), decode JPEG
        if (transfer_syntax.isEncapsulated()) {
            if (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64) {
                // WASM environment doesn't support JPEG decoding
                return errors.DicomError.UnsupportedTransferSyntax;
            }

            // Check if transfer syntax is JPEG 2000 (not supported)
            if (transfer_syntax == .JPEG2000Lossless or transfer_syntax == .JPEG2000) {
                return errors.DicomError.UnsupportedTransferSyntax;
            }

            // Extract JPEG frames
            var frames = try EncapsulatedPixelData.extractJPEGFrames(pixel_data, allocator);
            defer frames.deinit(allocator);

            if (frames.items.len == 0) {
                return errors.DicomError.InvalidPixelData;
            }

            // Decode first frame (single-frame image)
            const jpeg_frame = frames.items[0];

            // Decode based on transfer syntax
            const decoded = if (transfer_syntax == .JPEGLossless) blk: {
                const result = try jpeg_lossless.decodeJpegLossless(allocator, jpeg_frame);
                // JPEG Lossless decoder always outputs 8-bit data after windowing
                bits_allocated = 8;
                bits_stored = 8;
                break :blk result;
            } else blk: {
                const result = try stb.loadJpegFromMemory(allocator, jpeg_frame, 0);
                // STB always outputs 8-bit data
                bits_allocated = 8;
                bits_stored = 8;
                break :blk result;
            };

            // Update samples_per_pixel based on decoded channels
            samples_per_pixel = decoded.channels;

            decoded_data = decoded.data;
            owns_data = true;
        }

        return PixelData{
            .data = decoded_data,
            .rows = rows,
            .columns = columns,
            .bits_allocated = bits_allocated,
            .bits_stored = bits_stored,
            .samples_per_pixel = samples_per_pixel,
            .photometric_interpretation = photometric,
            .owns_data = owns_data,
        };
    }

    pub fn deinit(self: *PixelData, allocator: std.mem.Allocator) void {
        allocator.free(self.photometric_interpretation);
        if (self.owns_data) {
            allocator.free(self.data);
        }
    }

    /// Convert pixel data to 8-bit grayscale with automatic windowing
    pub fn toGrayscale8(self: PixelData, allocator: std.mem.Allocator) ![]u8 {
        const pixel_count = @as(usize, self.rows) * @as(usize, self.columns);
        const output = try allocator.alloc(u8, pixel_count);
        errdefer allocator.free(output);

        if (self.bits_allocated == 8 and self.samples_per_pixel == 1) {
            // Already 8-bit grayscale
            @memcpy(output, self.data[0..pixel_count]);
        } else if (self.bits_allocated == 16 and self.samples_per_pixel == 1) {
            // 16-bit grayscale - convert to 8-bit with auto-windowing
            // Find min and max values for windowing
            var min_val: u16 = std.math.maxInt(u16);
            var max_val: u16 = 0;

            for (0..pixel_count) |i| {
                const offset = i * 2;
                const value = std.mem.readInt(u16, self.data[offset..][0..2], .little);
                if (value < min_val) min_val = value;
                if (value > max_val) max_val = value;
            }

            // Map to 0-255 range
            const range = if (max_val > min_val) max_val - min_val else 1;
            for (0..pixel_count) |i| {
                const offset = i * 2;
                const value = std.mem.readInt(u16, self.data[offset..][0..2], .little);
                const normalized = @as(u32, value - min_val) * 255 / range;
                output[i] = @intCast(normalized);
            }
        } else if (self.samples_per_pixel == 3) {
            // 8-bit RGB - convert to grayscale
            for (0..pixel_count) |i| {
                const r = self.data[i * 3];
                const g = self.data[i * 3 + 1];
                const b = self.data[i * 3 + 2];
                // Use standard RGB to grayscale conversion
                output[i] = @intFromFloat(0.299 * @as(f32, @floatFromInt(r)) + 0.587 * @as(f32, @floatFromInt(g)) + 0.114 * @as(f32, @floatFromInt(b)));
            }
        } else {
            return errors.DicomError.InvalidPixelData;
        }

        // Handle photometric interpretation
        if (std.mem.eql(u8, std.mem.trim(u8, self.photometric_interpretation, &[_]u8{ ' ', 0 }), "MONOCHROME1")) {
            // Invert for MONOCHROME1
            for (output) |*pixel| {
                pixel.* = 255 - pixel.*;
            }
        }

        return output;
    }

    /// Convert to RGB (3 channels, 8-bit each)
    pub fn toRGB8(self: PixelData, allocator: std.mem.Allocator) ![]u8 {
        const grayscale = try self.toGrayscale8(allocator);
        defer allocator.free(grayscale);

        const rgb_size = grayscale.len * 3;
        const rgb = try allocator.alloc(u8, rgb_size);

        for (grayscale, 0..) |gray, i| {
            rgb[i * 3] = gray;
            rgb[i * 3 + 1] = gray;
            rgb[i * 3 + 2] = gray;
        }

        return rgb;
    }
};
