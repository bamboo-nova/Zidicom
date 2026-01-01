const std = @import("std");
const dicom_viewer = @import("dicom_viewer");

// Use aliases for convenience
const allocator_mod = dicom_viewer.wasm_allocator;
const memory_mod = dicom_viewer.wasm_memory;
const errors = dicom_viewer.errors;

/// Global WASM memory manager instance
var wasm_memory: ?memory_mod.WasmMemory = null;

/// Initialize WASM memory manager if not already initialized
fn ensureMemoryInit() void {
    if (wasm_memory == null) {
        wasm_memory = memory_mod.WasmMemory.init(allocator_mod.getGlobalAllocator());
    }
}

/// Allocate memory in WASM linear memory
/// Returns pointer to allocated memory as u32
export fn wasmAlloc(size: u32) u32 {
    ensureMemoryInit();
    const ptr = wasm_memory.?.alloc(size) catch {
        errors.setLastError("Failed to allocate {} bytes", .{size});
        return 0;
    };
    return ptr;
}

/// Free memory allocated by wasmAlloc
export fn wasmFree(ptr: u32, size: u32) void {
    if (wasm_memory) |*mem| {
        mem.free(ptr, size);
    }
}

/// Get the last error message pointer
export fn getLastError() u32 {
    const err_msg = errors.getLastError();
    return @intFromPtr(err_msg.ptr);
}

/// Get the last error message length
export fn getLastErrorLen() u32 {
    const err_msg = errors.getLastError();
    return @intCast(err_msg.len);
}

/// Get memory statistics (total allocated bytes)
export fn wasmGetMemoryStats() u32 {
    if (wasm_memory) |mem| {
        return @intCast(mem.getTotalAllocated());
    }
    return 0;
}

/// Simple test function to verify WASM module is working
export fn testAdd(a: u32, b: u32) u32 {
    return a + b;
}

/// Convert DICOM to RGB pixel data
/// Returns RGB data pointer and dimensions
export fn convertDicomToRGB(
    dicom_ptr: u32,
    dicom_len: u32,
    result_ptr_out: u32,
) u32 {
    ensureMemoryInit();

    const allocator = allocator_mod.getGlobalAllocator();

    // Get DICOM buffer
    const dicom_buffer = wasm_memory.?.getSlice(dicom_ptr, dicom_len) catch {
        errors.setLastError("Invalid DICOM buffer", .{});
        return 1;
    };

    // Parse DICOM
    const parser = dicom_viewer.Parser.init(allocator);
    var parse_result = parser.parse(dicom_buffer) catch |err| {
        errors.setLastError("Failed to parse DICOM: {}", .{err});
        return 1;
    };
    defer parse_result.file_meta.deinit(allocator);
    defer parse_result.dataset.deinit();

    // Get transfer syntax
    const transfer_syntax = parse_result.file_meta.getTransferSyntax() catch |err| {
        errors.setLastError("Failed to get transfer syntax: {}", .{err});
        return 1;
    };

    // Check if transfer syntax is supported in WASM
    if (transfer_syntax.isEncapsulated()) {
        const ts_name = transfer_syntax.getName();
        errors.setLastError("WASM environment does not support compressed DICOM files. Transfer Syntax: {s}. Please use uncompressed DICOM files (Explicit/Implicit VR Little Endian).", .{ts_name});
        return 1;
    }

    // Extract pixel data
    var pixel_data = dicom_viewer.PixelData.fromDataset(
        parse_result.dataset,
        transfer_syntax,
        allocator,
    ) catch |err| {
        errors.setLastError("Failed to extract pixel data: {}", .{err});
        return 1;
    };
    defer pixel_data.deinit(allocator);

    // Convert to RGB (8-bit, 3 channels)
    const pixel_count = @as(usize, pixel_data.rows) * @as(usize, pixel_data.columns);
    const rgb_size = pixel_count * 3;
    const rgb_data = allocator.alloc(u8, rgb_size) catch {
        errors.setLastError("Failed to allocate RGB buffer", .{});
        return 1;
    };
    defer allocator.free(rgb_data);

    // Convert pixel data to RGB based on format
    if (pixel_data.bits_allocated == 8 and pixel_data.samples_per_pixel == 1) {
        // 8-bit grayscale -> RGB
        for (0..pixel_count) |i| {
            const gray = pixel_data.data[i];
            rgb_data[i * 3] = gray;
            rgb_data[i * 3 + 1] = gray;
            rgb_data[i * 3 + 2] = gray;
        }
    } else if (pixel_data.bits_allocated == 8 and pixel_data.samples_per_pixel == 3) {
        // Already RGB
        @memcpy(rgb_data, pixel_data.data[0..rgb_size]);
    } else if (pixel_data.bits_allocated == 16 and pixel_data.samples_per_pixel == 1) {
        // 16-bit grayscale -> 8-bit RGB with auto-windowing
        var min_val: u16 = std.math.maxInt(u16);
        var max_val: u16 = 0;

        // Find min and max
        for (0..pixel_count) |i| {
            const offset = i * 2;
            const value = std.mem.readInt(u16, pixel_data.data[offset..][0..2], .little);
            if (value < min_val) min_val = value;
            if (value > max_val) max_val = value;
        }

        // Map to 0-255 range
        const range = if (max_val > min_val) max_val - min_val else 1;
        for (0..pixel_count) |i| {
            const offset = i * 2;
            const value = std.mem.readInt(u16, pixel_data.data[offset..][0..2], .little);
            const normalized = @as(u32, value - min_val) * 255 / range;
            const gray: u8 = @intCast(normalized);
            rgb_data[i * 3] = gray;
            rgb_data[i * 3 + 1] = gray;
            rgb_data[i * 3 + 2] = gray;
        }
    } else {
        errors.setLastError("Unsupported pixel format", .{});
        return 1;
    }

    // Handle photometric interpretation (invert for MONOCHROME1)
    const photometric_trimmed = std.mem.trim(u8, pixel_data.photometric_interpretation, &[_]u8{ ' ', 0 });
    if (std.mem.eql(u8, photometric_trimmed, "MONOCHROME1")) {
        for (rgb_data) |*pixel| {
            pixel.* = 255 - pixel.*;
        }
    }

    // Allocate memory for RGB data
    const rgb_ptr = wasm_memory.?.alloc(@intCast(rgb_data.len)) catch {
        errors.setLastError("Failed to allocate memory for RGB data", .{});
        return 1;
    };

    const rgb_slice = wasm_memory.?.getSlice(rgb_ptr, @intCast(rgb_data.len)) catch {
        errors.setLastError("Failed to get RGB slice", .{});
        return 1;
    };
    @memcpy(rgb_slice, rgb_data);

    // Write result: ptr (4 bytes), length (4 bytes), width (4 bytes), height (4 bytes)
    const out_slice = wasm_memory.?.getSlice(result_ptr_out, 16) catch {
        errors.setLastError("Invalid output pointer", .{});
        return 1;
    };
    std.mem.writeInt(u32, out_slice[0..4], rgb_ptr, .little);
    std.mem.writeInt(u32, out_slice[4..8], @intCast(rgb_data.len), .little);
    std.mem.writeInt(u32, out_slice[8..12], pixel_data.columns, .little);
    std.mem.writeInt(u32, out_slice[12..16], pixel_data.rows, .little);

    return 0; // Success
}

/// Extract metadata from DICOM and return as JSON
export fn extractMetadataJson(
    dicom_ptr: u32,
    dicom_len: u32,
    json_ptr_out: u32,
) u32 {
    ensureMemoryInit();

    const allocator = allocator_mod.getGlobalAllocator();

    // Get DICOM buffer
    const dicom_buffer = wasm_memory.?.getSlice(dicom_ptr, dicom_len) catch {
        errors.setLastError("Invalid DICOM buffer", .{});
        return 0;
    };

    // Parse DICOM
    const parser = dicom_viewer.Parser.init(allocator);
    var parse_result = parser.parse(dicom_buffer) catch |err| {
        errors.setLastError("Failed to parse DICOM: {}", .{err});
        return 0;
    };
    defer parse_result.file_meta.deinit(allocator);
    defer parse_result.dataset.deinit();

    // Extract metadata
    var metadata = dicom_viewer.Metadata.fromDataset(parse_result.dataset, allocator) catch |err| {
        errors.setLastError("Failed to extract metadata: {}", .{err});
        return 0;
    };
    defer metadata.deinit(allocator);

    // Convert to JSON
    const json = metadata.toJson(allocator) catch |err| {
        errors.setLastError("Failed to convert metadata to JSON: {}", .{err});
        return 0;
    };
    defer allocator.free(json);

    // Allocate memory for JSON and copy
    const json_ptr = wasm_memory.?.alloc(@intCast(json.len)) catch {
        errors.setLastError("Failed to allocate memory for JSON", .{});
        return 0;
    };

    const json_slice = wasm_memory.?.getSlice(json_ptr, @intCast(json.len)) catch {
        errors.setLastError("Failed to get JSON slice", .{});
        return 0;
    };
    @memcpy(json_slice, json);

    // Write pointer to output
    const out_slice = wasm_memory.?.getSlice(json_ptr_out, 8) catch {
        errors.setLastError("Invalid output pointer", .{});
        return 0;
    };
    std.mem.writeInt(u32, out_slice[0..4], json_ptr, .little);
    std.mem.writeInt(u32, out_slice[4..8], @intCast(json.len), .little);

    return 1; // Success
}

/// Get DICOM image dimensions
export fn getDicomDimensions(
    dicom_ptr: u32,
    dicom_len: u32,
    width_out: u32,
    height_out: u32,
) u32 {
    ensureMemoryInit();

    const allocator = allocator_mod.getGlobalAllocator();

    // Get DICOM buffer
    const dicom_buffer = wasm_memory.?.getSlice(dicom_ptr, dicom_len) catch {
        errors.setLastError("Invalid DICOM buffer", .{});
        return 1;
    };

    // Parse DICOM
    const parser = dicom_viewer.Parser.init(allocator);
    var parse_result = parser.parse(dicom_buffer) catch |err| {
        errors.setLastError("Failed to parse DICOM: {}", .{err});
        return 1;
    };
    defer parse_result.file_meta.deinit(allocator);
    defer parse_result.dataset.deinit();

    // Get dimensions
    const rows = parse_result.dataset.getValueAsU16(dicom_viewer.Tag.Rows, true) catch {
        errors.setLastError("Failed to get rows", .{});
        return 1;
    } orelse {
        errors.setLastError("Rows not found", .{});
        return 1;
    };

    const columns = parse_result.dataset.getValueAsU16(dicom_viewer.Tag.Columns, true) catch {
        errors.setLastError("Failed to get columns", .{});
        return 1;
    } orelse {
        errors.setLastError("Columns not found", .{});
        return 1;
    };

    // Write to output
    const width_slice = wasm_memory.?.getSlice(width_out, 4) catch {
        errors.setLastError("Invalid width output pointer", .{});
        return 1;
    };
    std.mem.writeInt(u32, width_slice[0..4], columns, .little);

    const height_slice = wasm_memory.?.getSlice(height_out, 4) catch {
        errors.setLastError("Invalid height output pointer", .{});
        return 1;
    };
    std.mem.writeInt(u32, height_slice[0..4], rows, .little);

    return 0; // Success
}
