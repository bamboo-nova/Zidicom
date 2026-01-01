const std = @import("std");
const dicom_viewer = @import("dicom_viewer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("DICOM Viewer - Medical Image Converter\n", .{});
        std.debug.print("Usage: {s} <dicom_file>\n", .{args[0]});
        std.debug.print("Output: <filename>.jpg and <filename>_metadata.json\n", .{});
        return;
    }

    const dicom_path = args[1];
    std.debug.print("Converting DICOM file: {s}\n", .{dicom_path});

    // Read DICOM file
    const file = try std.fs.cwd().openFile(dicom_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    // Parse DICOM file
    const parser = dicom_viewer.Parser.init(allocator);
    var result = try parser.parse(buffer);
    defer result.file_meta.deinit(allocator);
    defer result.dataset.deinit();

    std.debug.print("DICOM file parsed successfully\n", .{});

    // Print Transfer Syntax for debugging
    const ts = try result.file_meta.getTransferSyntax();
    std.debug.print("Transfer Syntax: {s} ({s})\n", .{ ts.getName(), ts.toUID() });
    std.debug.print("Is Encapsulated (Compressed): {}\n", .{ts.isEncapsulated()});

    // Extract pixel data
    var pixel_data = dicom_viewer.PixelData.fromDataset(result.dataset, ts, allocator) catch |err| {
        // Error message already printed by PixelData.fromDataset
        return err;
    };
    defer pixel_data.deinit(allocator);

    std.debug.print("Image size: {d}x{d}\n", .{ pixel_data.columns, pixel_data.rows });

    // Convert to RGB
    const rgb_data = try pixel_data.toRGB8(allocator);
    defer allocator.free(rgb_data);

    // Convert to JPEG
    const converter = dicom_viewer.converter.Converter.init(allocator);
    const jpeg_data = try converter.convertToImage(
        rgb_data,
        pixel_data.columns,
        pixel_data.rows,
        .{ .format = .JPEG, .quality = 90 },
    );
    defer allocator.free(jpeg_data);

    // Write JPEG file
    const output_jpg_path = try std.fmt.allocPrint(
        allocator,
        "{s}.jpg",
        .{std.fs.path.stem(dicom_path)},
    );
    defer allocator.free(output_jpg_path);

    const jpg_file = try std.fs.cwd().createFile(output_jpg_path, .{});
    defer jpg_file.close();
    try jpg_file.writeAll(jpeg_data);

    std.debug.print("JPEG image saved: {s}\n", .{output_jpg_path});

    // Extract metadata
    var metadata = try dicom_viewer.Metadata.fromDataset(result.dataset, allocator);
    defer metadata.deinit(allocator);

    // Convert metadata to JSON
    const json_str = try metadata.toJson(allocator);
    defer allocator.free(json_str);

    // Write JSON file
    const output_json_path = try std.fmt.allocPrint(
        allocator,
        "{s}_metadata.json",
        .{std.fs.path.stem(dicom_path)},
    );
    defer allocator.free(output_json_path);

    const json_file = try std.fs.cwd().createFile(output_json_path, .{});
    defer json_file.close();
    try json_file.writeAll(json_str);

    std.debug.print("Metadata JSON saved: {s}\n", .{output_json_path});
    std.debug.print("Conversion complete!\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
