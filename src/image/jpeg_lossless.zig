const std = @import("std");
const BitReader = @import("bitstream.zig").BitReader;
const HuffmanTable = @import("huffman.zig").HuffmanTable;
const decodeValue = @import("huffman.zig").decodeValue;
const getPredictedValue = @import("jpeg_lossless_predictor.zig").getPredictedValue;
const Marker = @import("jpeg_markers.zig").Marker;
const readMarker = @import("jpeg_markers.zig").readMarker;
const readSegmentLength = @import("jpeg_markers.zig").readSegmentLength;
const DecodedImage = @import("types.zig").DecodedImage;

pub const JpegLosslessError = error{
    InvalidMarker,
    UnsupportedFormat,
    InvalidFrameHeader,
    InvalidScanHeader,
    InvalidHuffmanTable,
    UnexpectedEndOfData,
    DecodingFailed,
    ArithmeticCodingNotSupported,
};

const ComponentInfo = struct {
    id: u8,
    h_sampling: u8,
    v_sampling: u8,
    quant_table_id: u8,
};

const ScanComponent = struct {
    component_index: u8,
    dc_table_id: u8,
    ac_table_id: u8,
};

pub const JpegLosslessDecoder = struct {
    allocator: std.mem.Allocator,

    // Frame header info
    precision: u8,
    height: u16,
    width: u16,
    num_components: u8,
    components: [4]ComponentInfo,

    // Scan info
    predictor: u8,
    point_transform: u8,

    // Huffman tables (4 DC, 4 AC - but for lossless we only use DC)
    huffman_dc: [4]HuffmanTable,

    // Restart interval
    restart_interval: u16,

    pub fn init(allocator: std.mem.Allocator) JpegLosslessDecoder {
        var decoder: JpegLosslessDecoder = undefined;
        decoder.allocator = allocator;
        decoder.precision = 0;
        decoder.height = 0;
        decoder.width = 0;
        decoder.num_components = 0;
        decoder.components = undefined;
        decoder.predictor = 1;
        decoder.point_transform = 0;
        decoder.restart_interval = 0;

        for (0..4) |i| {
            decoder.huffman_dc[i] = HuffmanTable.init();
        }

        return decoder;
    }

    pub fn decode(self: *JpegLosslessDecoder, jpeg_data: []const u8) !DecodedImage {
        var pos: usize = 0;

        std.debug.print("JPEG Lossless decoder: Starting decode, data size = {d}\n", .{jpeg_data.len});

        // Check for SOI marker
        const soi = try readMarker(jpeg_data, &pos);
        if (soi != @intFromEnum(Marker.SOI)) {
            return JpegLosslessError.InvalidMarker;
        }
        std.debug.print("Found SOI marker\n", .{});

        // Parse markers until SOS
        while (pos < jpeg_data.len) {
            const marker = try readMarker(jpeg_data, &pos);
            std.debug.print("Marker: 0x{X:0>2} at pos {d}\n", .{ marker, pos });

            if (Marker.isSOF(marker)) {
                try self.parseSOF(jpeg_data, &pos, marker);
                std.debug.print("Parsed SOF: {d}x{d}, {d}-bit, {d} components\n", .{ self.width, self.height, self.precision, self.num_components });
            } else if (marker == @intFromEnum(Marker.DHT)) {
                try self.parseDHT(jpeg_data, &pos);
                std.debug.print("Parsed DHT\n", .{});
            } else if (marker == @intFromEnum(Marker.DRI)) {
                try self.parseDRI(jpeg_data, &pos);
                std.debug.print("Parsed DRI: interval = {d}\n", .{self.restart_interval});
            } else if (marker == @intFromEnum(Marker.SOS)) {
                std.debug.print("Found SOS, starting scan decode...\n", .{});
                return try self.parseSOS(jpeg_data, &pos);
            } else if (marker == @intFromEnum(Marker.EOI)) {
                return JpegLosslessError.UnexpectedEndOfData;
            } else {
                // Skip unknown marker
                if (marker >= 0xD0 and marker <= 0xD9) {
                    // Standalone marker, no data
                    continue;
                }
                const length = try readSegmentLength(jpeg_data, &pos);
                std.debug.print("Skipping marker, length = {d}\n", .{length});
                pos += length - 2; // length includes the 2 bytes for length itself
            }
        }

        return JpegLosslessError.UnexpectedEndOfData;
    }

    fn parseSOF(self: *JpegLosslessDecoder, data: []const u8, pos: *usize, marker: u8) !void {
        if (!Marker.isLossless(marker)) {
            return JpegLosslessError.UnsupportedFormat;
        }

        if (Marker.usesArithmeticCoding(marker)) {
            return JpegLosslessError.ArithmeticCodingNotSupported;
        }

        const length = try readSegmentLength(data, pos);
        const start_pos = pos.*;

        self.precision = data[pos.*];
        pos.* += 1;

        self.height = std.mem.readInt(u16, data[pos.*..][0..2], .big);
        pos.* += 2;

        self.width = std.mem.readInt(u16, data[pos.*..][0..2], .big);
        pos.* += 2;

        self.num_components = data[pos.*];
        pos.* += 1;

        if (self.num_components > 4) {
            return JpegLosslessError.InvalidFrameHeader;
        }

        for (0..self.num_components) |i| {
            self.components[i].id = data[pos.*];
            pos.* += 1;

            const sampling = data[pos.*];
            pos.* += 1;
            self.components[i].h_sampling = sampling >> 4;
            self.components[i].v_sampling = sampling & 0x0F;

            self.components[i].quant_table_id = data[pos.*];
            pos.* += 1;
        }

        // Verify we read the correct amount
        const bytes_read = pos.* - start_pos;
        if (bytes_read != length - 2) {
            pos.* = start_pos + length - 2;
        }
    }

    fn parseDHT(self: *JpegLosslessDecoder, data: []const u8, pos: *usize) !void {
        const length = try readSegmentLength(data, pos);
        const end_pos = pos.* + length - 2;

        while (pos.* < end_pos) {
            const table_info = data[pos.*];
            pos.* += 1;

            _ = table_info >> 4; // table_class: 0 = DC, 1 = AC (not used for lossless)
            const table_id = table_info & 0x0F;

            if (table_id >= 4) {
                return JpegLosslessError.InvalidHuffmanTable;
            }

            // For lossless, we only use DC tables
            var table = &self.huffman_dc[table_id];

            // Read number of codes of each length (1-16)
            var total_codes: usize = 0;
            for (1..17) |i| {
                table.bits[i] = data[pos.*];
                total_codes += table.bits[i];
                pos.* += 1;
            }

            if (total_codes > 256) {
                return JpegLosslessError.InvalidHuffmanTable;
            }

            // Read Huffman values
            for (0..total_codes) |i| {
                table.huffval[i] = data[pos.*];
                pos.* += 1;
            }

            // Build decoding tables
            try table.build();
        }
    }

    fn parseDRI(self: *JpegLosslessDecoder, data: []const u8, pos: *usize) !void {
        const length = try readSegmentLength(data, pos);
        if (length != 4) {
            return JpegLosslessError.UnexpectedEndOfData;
        }

        self.restart_interval = std.mem.readInt(u16, data[pos.*..][0..2], .big);
        pos.* += 2;
    }

    fn parseSOS(self: *JpegLosslessDecoder, data: []const u8, pos: *usize) !DecodedImage {
        const length = try readSegmentLength(data, pos);
        const start_pos = pos.*;

        const num_scan_components = data[pos.*];
        pos.* += 1;

        if (num_scan_components != self.num_components) {
            // For simplicity, we only support scans with all components
            return JpegLosslessError.UnsupportedFormat;
        }

        var scan_components: [4]ScanComponent = undefined;

        for (0..num_scan_components) |i| {
            const component_selector = data[pos.*];
            pos.* += 1;

            const table_ids = data[pos.*];
            pos.* += 1;

            scan_components[i].component_index = component_selector;
            scan_components[i].dc_table_id = table_ids >> 4;
            scan_components[i].ac_table_id = table_ids & 0x0F;
        }

        // Read scan parameters
        self.predictor = data[pos.*];
        pos.* += 1;

        _ = data[pos.*]; // se: Should be 0 for lossless (not used)
        pos.* += 1;

        const ah_al = data[pos.*];
        pos.* += 1;
        self.point_transform = ah_al & 0x0F;

        // Start of scan data
        const bytes_read = pos.* - start_pos;
        if (bytes_read != length - 2) {
            pos.* = start_pos + length - 2;
        }

        // Decode scan data
        return try self.decodeScan(data[pos.*..], scan_components[0..num_scan_components]);
    }

    fn decodeScan(self: *JpegLosslessDecoder, scan_data: []const u8, scan_components: []const ScanComponent) !DecodedImage {
        // Allocate output buffer (i32 for intermediate values)
        const pixel_count = @as(usize, self.height) * @as(usize, self.width) * @as(usize, self.num_components);
        std.debug.print("Decoding scan: {d}x{d}, {d} components, pixel_count = {d}\n", .{ self.width, self.height, self.num_components, pixel_count });
        std.debug.print("Scan data size: {d} bytes\n", .{scan_data.len});
        std.debug.print("Predictor: {d}, Point transform: {d}\n", .{ self.predictor, self.point_transform });

        const output_i32 = try self.allocator.alloc(i32, pixel_count);
        defer self.allocator.free(output_i32);
        @memset(output_i32, 0);

        var reader = BitReader.init(scan_data);
        var restart_count: u32 = 0;

        // Decode in raster scan order
        for (0..self.height) |y| {
            if (y % 100 == 0) {
                std.debug.print("Decoding row {d}/{d}...\n", .{ y, self.height });
            }
            for (0..self.width) |x| {
                for (0..self.num_components) |comp| {
                    // Check for restart marker
                    if (self.restart_interval > 0 and restart_count >= self.restart_interval) {
                        reader.alignToByte();
                        // Skip restart marker (we don't validate it for simplicity)
                        try reader.skipBytes(2);
                        restart_count = 0;
                    }

                    const table_id = scan_components[comp].dc_table_id;
                    if (table_id >= 4) {
                        return JpegLosslessError.InvalidHuffmanTable;
                    }

                    // Decode difference using Huffman table
                    const ssss = try self.huffman_dc[table_id].decode(&reader);
                    const diff = try decodeValue(&reader, ssss);

                    // Get predicted value
                    const pred = getPredictedValue(
                        output_i32,
                        x,
                        y,
                        comp,
                        self.width,
                        self.num_components,
                        self.predictor,
                        self.precision,
                        self.point_transform,
                    );

                    // Reconstruct pixel value
                    const value = pred + diff;
                    const idx = (y * self.width + x) * self.num_components + comp;
                    output_i32[idx] = value;

                    // Debug: print first few pixels
                    if (y == 0 and x < 5) {
                        std.debug.print("Pixel[{d},{d}]: ssss={d}, diff={d}, pred={d}, value={d}\n", .{ x, y, ssss, diff, pred, value });
                    }
                }

                restart_count += 1;
            }
        }

        // Convert to u8 or u16 based on precision
        if (self.precision <= 8) {
            const output = try self.allocator.alloc(u8, pixel_count);
            for (output_i32, 0..) |val, i| {
                output[i] = @intCast(@max(0, @min(255, val)));
            }
            return DecodedImage{
                .data = output,
                .width = self.width,
                .height = self.height,
                .channels = @intCast(self.num_components),
            };
        } else {
            // For >8 bit, we need to downscale to 8-bit with proper windowing
            // First find min and max values for auto-windowing
            var min_val: i32 = std.math.maxInt(i32);
            var max_val: i32 = std.math.minInt(i32);

            for (output_i32) |val| {
                min_val = @min(min_val, val);
                max_val = @max(max_val, val);
            }

            std.debug.print("Converting {d}-bit to 8-bit with windowing: min={d}, max={d}\n", .{ self.precision, min_val, max_val });

            const output = try self.allocator.alloc(u8, pixel_count);
            const range = if (max_val > min_val) max_val - min_val else 1;

            for (output_i32, 0..) |val, i| {
                const normalized = @divTrunc((@as(i64, val) - @as(i64, min_val)) * 255, @as(i64, range));
                output[i] = @intCast(@max(0, @min(255, normalized)));

                if (i < 10) {
                    std.debug.print("output_i32[{d}]={d} -> normalized={d} -> output={d}\n", .{ i, val, normalized, output[i] });
                }
            }
            return DecodedImage{
                .data = output,
                .width = self.width,
                .height = self.height,
                .channels = @intCast(self.num_components),
            };
        }
    }
};

/// Decode JPEG Lossless from memory
pub fn decodeJpegLossless(
    allocator: std.mem.Allocator,
    jpeg_data: []const u8,
) !DecodedImage {
    var decoder = JpegLosslessDecoder.init(allocator);
    return try decoder.decode(jpeg_data);
}
