const std = @import("std");

/// Comprehensive error set for DICOM parsing and conversion
pub const DicomError = error{
    // File format errors
    InvalidPreamble,
    InvalidPrefix,
    InvalidFileMeta,

    // Parsing errors
    UnexpectedEndOfData,
    InvalidTag,
    InvalidVR,
    InvalidLength,
    UnsupportedTransferSyntax,

    // Pixel data errors
    PixelDataNotFound,
    InvalidPixelData,
    UnsupportedPhotometricInterpretation,

    // Conversion errors
    JPEGEncodingFailed,
    PNGEncodingFailed,
    JPEGDecodingFailed,

    // Memory errors
    OutOfMemory,

    // General errors
    InvalidInput,
    InternalError,
};

/// Thread-local error context for WASM
var last_error_buffer: [1024]u8 = undefined;
var last_error_len: usize = 0;

/// Set the last error message with formatted string
pub fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const result = std.fmt.bufPrint(&last_error_buffer, fmt, args) catch |err| {
        // If error formatting fails, write the error itself
        const err_result = std.fmt.bufPrint(
            &last_error_buffer,
            "Error formatting error: {any}",
            .{err},
        ) catch "";
        last_error_len = err_result.len;
        return;
    };
    last_error_len = result.len;
}

/// Get the last error message
pub fn getLastError() []const u8 {
    return last_error_buffer[0..last_error_len];
}

/// Clear the last error
pub fn clearLastError() void {
    last_error_len = 0;
}

test "setLastError and getLastError" {
    setLastError("Test error: {s}", .{"details"});
    const err_msg = getLastError();
    try std.testing.expectEqualStrings("Test error: details", err_msg);
}

test "clearLastError" {
    setLastError("Test error", .{});
    try std.testing.expect(getLastError().len > 0);
    clearLastError();
    try std.testing.expect(getLastError().len == 0);
}
