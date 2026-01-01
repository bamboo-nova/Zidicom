const std = @import("std");
const dicom_viewer = @import("dicom_viewer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <dicom_file>\n", .{args[0]});
        return;
    }

    const dicom_path = args[1];

    // Read DICOM file
    const file = try std.fs.cwd().openFile(dicom_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const dicom_data = try allocator.alloc(u8, file_size);
    defer allocator.free(dicom_data);

    _ = try file.readAll(dicom_data);

    // Parse DICOM
    const parser = dicom_viewer.Parser.init(allocator);
    var parse_result = try parser.parse(dicom_data);
    defer parse_result.file_meta.deinit(allocator);
    defer parse_result.dataset.deinit();

    // Get transfer syntax
    const transfer_syntax = try parse_result.file_meta.getTransferSyntax();

    // Extract pixel data
    var pixel_data = try dicom_viewer.PixelData.fromDataset(
        parse_result.dataset,
        transfer_syntax,
        allocator,
    );
    defer pixel_data.deinit(allocator);

    // Convert to RGB
    const rgb_data = try pixel_data.toRGB8(allocator);
    defer allocator.free(rgb_data);

    // Output to file: width (4 bytes) + height (4 bytes) + RGB data
    const output_path = if (args.len >= 3) args[2] else blk: {
        const base = std.fs.path.basename(dicom_path);
        const name = if (std.mem.lastIndexOf(u8, base, ".")) |idx| base[0..idx] else base;
        const out = try std.fmt.allocPrint(allocator, "{s}.rgb", .{name});
        break :blk out;
    };
    defer if (args.len < 3) allocator.free(output_path);

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Write header
    var header: [8]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], pixel_data.columns, .little);
    std.mem.writeInt(u32, header[4..8], pixel_data.rows, .little);
    try output_file.writeAll(&header);

    // Write RGB data
    try output_file.writeAll(rgb_data);
}
