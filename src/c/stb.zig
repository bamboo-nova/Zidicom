const std = @import("std");
const DecodedImage = @import("../image/types.zig").DecodedImage;

// External C functions from STB
extern "c" fn stb_write_jpg_to_memory(
    output: *?[*]u8,
    output_len: *usize,
    w: c_int,
    h: c_int,
    comp: c_int,
    data: *const anyopaque,
    quality: c_int,
) c_int;

extern "c" fn stb_write_png_to_memory(
    output: *?[*]u8,
    output_len: *usize,
    w: c_int,
    h: c_int,
    comp: c_int,
    data: *const anyopaque,
    stride_in_bytes: c_int,
) c_int;

extern "c" fn stbi_load_from_memory(
    buffer: [*c]const u8,
    len: c_int,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) [*c]u8;

extern "c" fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

extern "c" fn stbi_failure_reason() [*c]const u8;

extern "c" fn free(ptr: ?*anyopaque) void;

pub const STBError = error{
    EncodingFailed,
    DecodingFailed,
    OutOfMemory,
};

/// Write JPEG to memory
pub fn writeJpegToMemory(
    allocator: std.mem.Allocator,
    data: []const u8,
    width: u16,
    height: u16,
    components: u8,
    quality: u8,
) ![]u8 {
    var output: ?[*]u8 = null;
    var output_len: usize = 0;

    const result = stb_write_jpg_to_memory(
        &output,
        &output_len,
        @as(c_int, width),
        @as(c_int, height),
        @as(c_int, components),
        data.ptr,
        @as(c_int, quality),
    );

    if (result == 0 or output == null) {
        return STBError.EncodingFailed;
    }

    const output_slice = output.?[0..output_len];
    const result_data = try allocator.dupe(u8, output_slice);

    // Free the C-allocated memory
    free(output);

    return result_data;
}

/// Write PNG to memory
pub fn writePngToMemory(
    allocator: std.mem.Allocator,
    data: []const u8,
    width: u16,
    height: u16,
    components: u8,
) ![]u8 {
    var output: ?[*]u8 = null;
    var output_len: usize = 0;

    const stride = @as(c_int, width) * @as(c_int, components);

    const result = stb_write_png_to_memory(
        &output,
        &output_len,
        @as(c_int, width),
        @as(c_int, height),
        @as(c_int, components),
        data.ptr,
        stride,
    );

    if (result == 0 or output == null) {
        return STBError.EncodingFailed;
    }

    const output_slice = output.?[0..output_len];
    const result_data = try allocator.dupe(u8, output_slice);

    // Free the C-allocated memory
    free(output);

    return result_data;
}

/// Decode JPEG from memory
pub fn loadJpegFromMemory(
    allocator: std.mem.Allocator,
    jpeg_data: []const u8,
    desired_channels: u8,
) !DecodedImage {
    var width: c_int = 0;
    var height: c_int = 0;
    var channels: c_int = 0;

    const decoded_ptr = stbi_load_from_memory(
        jpeg_data.ptr,
        @intCast(jpeg_data.len),
        &width,
        &height,
        &channels,
        @intCast(desired_channels),
    ) orelse {
        const reason = stbi_failure_reason();
        if (reason != null) {
            std.debug.print("STB decoding failed: {s}\n", .{std.mem.span(reason)});
        }
        return STBError.DecodingFailed;
    };

    const actual_channels = if (desired_channels > 0) desired_channels else @as(u8, @intCast(channels));
    const data_len = @as(usize, @intCast(width)) * @as(usize, @intCast(height)) * @as(usize, actual_channels);
    const decoded_slice = decoded_ptr[0..data_len];

    // Copy to allocator-managed memory
    const result_data = try allocator.dupe(u8, decoded_slice);

    // Free STB-allocated memory
    stbi_image_free(decoded_ptr);

    return .{
        .data = result_data,
        .width = @intCast(width),
        .height = @intCast(height),
        .channels = actual_channels,
    };
}
