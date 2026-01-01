const std = @import("std");
const FileMeta = @import("file_meta.zig").FileMeta;
const DataElement = @import("data_element.zig").DataElement;
const Tag = @import("data_element.zig").Tag;
const VR = @import("vr.zig").VR;
const TransferSyntax = @import("transfer_syntax.zig").TransferSyntax;
const ByteReader = @import("../utils/byte_reader.zig").ByteReader;
const errors = @import("../utils/errors.zig");

/// DICOM Dataset containing parsed elements
pub const Dataset = struct {
    elements: std.ArrayListUnmanaged(DataElement),
    buffer: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8) Dataset {
        return .{
            .elements = .{},
            .buffer = buffer,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Dataset) void {
        self.elements.deinit(self.allocator);
    }

    /// Find a data element by tag
    pub fn findElement(self: Dataset, tag: Tag) ?DataElement {
        for (self.elements.items) |elem| {
            if (elem.tag.eql(tag)) {
                return elem;
            }
        }
        return null;
    }

    /// Get element value as string
    pub fn getValueAsString(self: Dataset, tag: Tag, allocator: std.mem.Allocator) !?[]const u8 {
        const elem = self.findElement(tag) orelse return null;
        return try elem.getValueAsString(self.buffer, allocator);
    }

    /// Get element value as u16
    pub fn getValueAsU16(self: Dataset, tag: Tag, is_little_endian: bool) !?u16 {
        const elem = self.findElement(tag) orelse return null;
        return try elem.getValueAsU16(self.buffer, is_little_endian);
    }

    /// Get element value as u32
    pub fn getValueAsU32(self: Dataset, tag: Tag, is_little_endian: bool) !?u32 {
        const elem = self.findElement(tag) orelse return null;
        return try elem.getValueAsU32(self.buffer, is_little_endian);
    }
};

/// Main DICOM Parser
pub const Parser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{ .allocator = allocator };
    }

    /// Parse DICOM file and return dataset
    pub fn parse(self: Parser, buffer: []const u8) !struct { file_meta: FileMeta, dataset: Dataset } {
        // Parse file meta information
        var file_meta = try FileMeta.parse(buffer, self.allocator);
        errdefer file_meta.deinit(self.allocator);

        // Get transfer syntax
        const transfer_syntax = try file_meta.getTransferSyntax();
        const is_little_endian = transfer_syntax.isLittleEndian();
        const is_explicit_vr = transfer_syntax.isExplicitVR();

        // Initialize dataset
        var dataset = Dataset.init(self.allocator, buffer);
        errdefer dataset.deinit();

        // Parse dataset starting from data_set_start_offset
        const data_start = file_meta.data_set_start_offset;
        if (data_start >= buffer.len) {
            return .{ .file_meta = file_meta, .dataset = dataset };
        }

        var reader = ByteReader.init(buffer[data_start..], is_little_endian);

        while (!reader.atEnd() and reader.remaining() >= 8) {
            const elem = self.parseDataElement(&reader, is_explicit_vr, data_start) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            try dataset.elements.append(self.allocator, elem);
        }

        return .{ .file_meta = file_meta, .dataset = dataset };
    }

    /// Parse a single data element
    fn parseDataElement(
        self: Parser,
        reader: *ByteReader,
        is_explicit_vr: bool,
        base_offset: usize,
    ) !DataElement {
        _ = self;

        const start_pos = reader.getPos();

        // --- tag ---
        const tag_group = try reader.readU16();
        const tag_element = try reader.readU16();

        // Stop parsing if we encounter invalid tags (group 0x0000 or all zeros)
        if (tag_group == 0x0000 and tag_element == 0x0000) {
            return error.EndOfStream;
        }

        const tag = Tag{ .group = tag_group, .element = tag_element };

        var vr: VR = undefined;
        var value_length: u32 = undefined;

        if (is_explicit_vr) {
            const vr_bytes = try reader.readBytes(2);

            // Validate VR - catch invalid VR errors
            vr = VR.fromString(vr_bytes) catch {
                return error.EndOfStream;
            };

            if (vr.hasExplicitLength()) {
                try reader.skip(2);
                value_length = try reader.readU32();
            } else {
                value_length = try reader.readU16();
            }
        } else {
            vr = VR.inferFromTag(tag);
            value_length = try reader.readU32();
        }

        // Undefined length (sequence or encapsulated pixel data)
        if (value_length == 0xFFFFFFFF) {
            const value_start_offset = base_offset + reader.getPos();

            // Find the sequence delimiter (FFFE,E0DD) to determine the actual length
            const start_pos_for_scan = reader.getPos();
            var actual_length: u32 = 0;

            while (!reader.atEnd() and reader.remaining() >= 8) {
                const scan_pos = reader.getPos();
                const next_tag_group = try reader.readU16();
                const next_tag_elem = try reader.readU16();

                if (next_tag_group == 0xFFFE and next_tag_elem == 0xE0DD) {
                    // Found sequence delimiter
                    // Read and skip the length field (should be 0)
                    _ = try reader.readU32();
                    actual_length = @intCast(scan_pos - start_pos_for_scan);
                    break;
                } else if (next_tag_group == 0xFFFE and next_tag_elem == 0xE000) {
                    // Item tag - skip item and continue
                    const item_length = try reader.readU32();
                    if (item_length > 0 and item_length != 0xFFFFFFFF) {
                        try reader.skip(item_length);
                    }
                } else {
                    // Not part of this sequence, we went too far
                    return error.InvalidLength;
                }
            }

            return DataElement{
                .tag = tag,
                .vr = vr,
                .value_length = actual_length,
                .value_offset = value_start_offset,
            };
        }

        const value_offset = base_offset + reader.getPos();

        if (value_length > 0) {
            try reader.skip(value_length);
        }

        // Safety check: ensure we made progress
        if (reader.getPos() == start_pos) {
            return error.EndOfStream;
        }

        return DataElement{
            .tag = tag,
            .vr = vr,
            .value_length = value_length,
            .value_offset = value_offset,
        };
    }
};

test "Parser basic" {
    const allocator = std.testing.allocator;

    // Create minimal DICOM file
    var buffer: [512]u8 = undefined;
    @memset(&buffer, 0);

    // Preamble and prefix
    buffer[128] = 'D';
    buffer[129] = 'I';
    buffer[130] = 'C';
    buffer[131] = 'M';

    // Transfer Syntax UID (0002,0010)
    var pos: usize = 132;
    buffer[pos] = 0x02;
    buffer[pos + 1] = 0x00;
    buffer[pos + 2] = 0x10;
    buffer[pos + 3] = 0x00;
    buffer[pos + 4] = 'U';
    buffer[pos + 5] = 'I';
    const ts_uid = "1.2.840.10008.1.2.1";
    buffer[pos + 6] = @intCast(ts_uid.len);
    buffer[pos + 7] = 0x00;
    @memcpy(buffer[pos + 8 .. pos + 8 + ts_uid.len], ts_uid);
    pos += 8 + ts_uid.len;

    // Media Storage SOP Class UID (0002,0002)
    buffer[pos] = 0x02;
    buffer[pos + 1] = 0x00;
    buffer[pos + 2] = 0x02;
    buffer[pos + 3] = 0x00;
    buffer[pos + 4] = 'U';
    buffer[pos + 5] = 'I';
    const sop_class = "1.2.840.10008.5.1.4.1.1.2";
    buffer[pos + 6] = @intCast(sop_class.len);
    buffer[pos + 7] = 0x00;
    @memcpy(buffer[pos + 8 .. pos + 8 + sop_class.len], sop_class);
    pos += 8 + sop_class.len;

    // Media Storage SOP Instance UID (0002,0003)
    buffer[pos] = 0x02;
    buffer[pos + 1] = 0x00;
    buffer[pos + 2] = 0x03;
    buffer[pos + 3] = 0x00;
    buffer[pos + 4] = 'U';
    buffer[pos + 5] = 'I';
    const sop_instance = "1.2.3.4.5.6.7.8.9";
    buffer[pos + 6] = @intCast(sop_instance.len);
    buffer[pos + 7] = 0x00;
    @memcpy(buffer[pos + 8 .. pos + 8 + sop_instance.len], sop_instance);
    pos += 8 + sop_instance.len;

    // Use only the actual data size, not the entire buffer
    const parser = Parser.init(allocator);
    var result = try parser.parse(buffer[0..pos]);
    defer result.file_meta.deinit(allocator);
    defer result.dataset.deinit();

    try std.testing.expectEqualStrings("DICM", &result.file_meta.prefix);
}
