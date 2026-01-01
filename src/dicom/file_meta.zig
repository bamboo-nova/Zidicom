const std = @import("std");
const ByteReader = @import("../utils/byte_reader.zig").ByteReader;
const VR = @import("vr.zig").VR;
const Tag = @import("data_element.zig").Tag;
const DataElement = @import("data_element.zig").DataElement;
const TransferSyntax = @import("transfer_syntax.zig").TransferSyntax;
const errors = @import("../utils/errors.zig");

// 「free するなら、必ず自分で alloc したものだけにする」
const OwnedSlice = struct {
    slice: []u8,
    owned: bool,
};

/// DICOM File Meta Information
pub const FileMeta = struct {
    preamble: [128]u8,
    prefix: [4]u8, // Should be "DICM"
    transfer_syntax_uid: OwnedSlice,
    media_storage_sop_class_uid: OwnedSlice,
    media_storage_sop_instance_uid: OwnedSlice,
    implementation_class_uid: ?OwnedSlice,
    file_meta_information_group_length: u32,
    data_set_start_offset: usize, // Where the main dataset begins

    /// Parse DICOM file meta information
    pub fn parse(buffer: []const u8, allocator: std.mem.Allocator) !FileMeta {
        if (buffer.len < 132) {
            return errors.DicomError.InvalidFileMeta;
        }

        var result: FileMeta = undefined;

        // Copy preamble (128 bytes)
        @memcpy(&result.preamble, buffer[0..128]);

        // Check prefix "DICM"
        @memcpy(&result.prefix, buffer[128..132]);
        if (!std.mem.eql(u8, &result.prefix, "DICM")) {
            return errors.DicomError.InvalidPrefix;
        }

        // Parse file meta information elements
        // File Meta Information is always Explicit VR Little Endian
        var reader = ByteReader.init(buffer[132..], true);
        var transfer_syntax_uid_opt: ?OwnedSlice = null;
        var media_storage_sop_class_uid_opt: ?OwnedSlice = null;
        var media_storage_sop_instance_uid_opt: ?OwnedSlice = null;
        var implementation_class_uid_opt: ?OwnedSlice = null;
        var group_length: u32 = 0;

        // Parse file meta elements until we leave group 0x0002
        // Safety: limit to reasonable number of iterations
        var iteration_count: usize = 0;
        const max_iterations = 100;

        while (!reader.atEnd() and iteration_count < max_iterations) : (iteration_count += 1) {
            // Need at least 4 bytes for tag
            if (reader.remaining() < 4) break;

            const tag_group = try reader.readU16();
            const tag_element = try reader.readU16();
            const tag = Tag{ .group = tag_group, .element = tag_element };

            // Stop when we leave group 0x0002 (file meta information)
            if (tag.group != 0x0002) {
                // Reset position to start of this tag
                try reader.setPos(reader.getPos() - 4);
                break;
            }

            // Read VR (2 bytes)
            if (reader.remaining() < 2) return errors.DicomError.InvalidFileMeta;
            const vr_bytes = try reader.readBytes(2);
            const vr = try VR.fromString(vr_bytes);

            // Read value length
            var value_length: u32 = 0;
            if (vr.hasExplicitLength()) {
                // 2 bytes reserved, then 4 bytes length
                if (reader.remaining() < 6) return errors.DicomError.InvalidFileMeta;
                try reader.skip(2);
                value_length = try reader.readU32();
            } else {
                // 2 bytes length
                if (reader.remaining() < 2) return errors.DicomError.InvalidFileMeta;
                value_length = try reader.readU16();
            }

            // Read value
            if (reader.remaining() < value_length) return errors.DicomError.InvalidFileMeta;
            const value_data = try reader.readBytes(value_length);

            // Handle specific tags
            if (tag.eql(Tag.FileMetaInformationGroupLength)) {
                if (value_data.len >= 4) {
                    group_length = std.mem.readInt(u32, value_data[0..4], .little);
                    // Group length is the number of bytes AFTER this element
                    // So we need to add the current position to get the absolute end
                }
            } else if (tag.eql(Tag.TransferSyntaxUID)) {
                const slice = try allocator.dupe(u8, value_data);
                transfer_syntax_uid_opt = OwnedSlice{
                    .slice = slice,
                    .owned = true,
                };
            } else if (tag.eql(Tag.MediaStorageSOPClassUID)) {
                const slice = try allocator.dupe(u8, value_data);
                media_storage_sop_class_uid_opt = OwnedSlice{
                    .slice = slice,
                    .owned = true,
                };
            } else if (tag.eql(Tag.MediaStorageSOPInstanceUID)) {
                const slice = try allocator.dupe(u8, value_data);
                media_storage_sop_instance_uid_opt = OwnedSlice{
                    .slice = slice,
                    .owned = true,
                };
            } else if (tag.eql(Tag.ImplementationClassUID)) {
                const slice = try allocator.dupe(u8, value_data);
                implementation_class_uid_opt = OwnedSlice{
                    .slice = slice,
                    .owned = true,
                };
            }
        }

        result.transfer_syntax_uid = transfer_syntax_uid_opt orelse return errors.DicomError.InvalidFileMeta;
        result.media_storage_sop_class_uid = media_storage_sop_class_uid_opt orelse return errors.DicomError.InvalidFileMeta;
        result.media_storage_sop_instance_uid = media_storage_sop_instance_uid_opt orelse return errors.DicomError.InvalidFileMeta;
        result.implementation_class_uid = implementation_class_uid_opt;
        result.file_meta_information_group_length = group_length;
        result.data_set_start_offset = 132 + reader.getPos();

        return result;
    }

    /// Free allocated memory
    pub fn deinit(self: *FileMeta, allocator: std.mem.Allocator) void {
        if (self.transfer_syntax_uid.owned)
            allocator.free(self.transfer_syntax_uid.slice);

        if (self.media_storage_sop_class_uid.owned)
            allocator.free(self.media_storage_sop_class_uid.slice);

        if (self.media_storage_sop_instance_uid.owned)
            allocator.free(self.media_storage_sop_instance_uid.slice);

        if (self.implementation_class_uid) |uid| {
            if (uid.owned)
                allocator.free(uid.slice);
        }
    }

    /// Validate file meta information
    pub fn validate(self: FileMeta) !void {
        if (!std.mem.eql(u8, &self.prefix, "DICM")) {
            return errors.DicomError.InvalidPrefix;
        }
        if (self.transfer_syntax_uid.len == 0) {
            return errors.DicomError.InvalidFileMeta;
        }
    }

    /// Get transfer syntax enum
    pub fn getTransferSyntax(self: FileMeta) !TransferSyntax {
        return TransferSyntax.fromUID(self.transfer_syntax_uid.slice);
    }
};

test "FileMeta parse minimal" {
    const allocator = std.testing.allocator;

    // Create minimal DICOM file meta
    var buffer: [512]u8 = undefined;
    @memset(&buffer, 0);

    // Preamble (128 bytes of zeros)
    // Prefix "DICM" at position 128
    buffer[128] = 'D';
    buffer[129] = 'I';
    buffer[130] = 'C';
    buffer[131] = 'M';

    // File Meta Information Group Length (0002,0000) VR=UL
    var pos: usize = 132;
    buffer[pos] = 0x02; // group low
    buffer[pos + 1] = 0x00; // group high
    buffer[pos + 2] = 0x00; // element low
    buffer[pos + 3] = 0x00; // element high
    buffer[pos + 4] = 'U'; // VR
    buffer[pos + 5] = 'L';
    buffer[pos + 6] = 0x04; // length low
    buffer[pos + 7] = 0x00; // length high
    buffer[pos + 8] = 0x00; // value (group length = 0 for simplicity)
    buffer[pos + 9] = 0x00;
    buffer[pos + 10] = 0x00;
    buffer[pos + 11] = 0x00;
    pos += 12;

    // Transfer Syntax UID (0002,0010) VR=UI
    buffer[pos] = 0x02; // group low
    buffer[pos + 1] = 0x00; // group high
    buffer[pos + 2] = 0x10; // element low
    buffer[pos + 3] = 0x00; // element high
    buffer[pos + 4] = 'U'; // VR
    buffer[pos + 5] = 'I';
    const ts_uid = "1.2.840.10008.1.2.1"; // Explicit VR Little Endian
    buffer[pos + 6] = @intCast(ts_uid.len); // length low
    buffer[pos + 7] = 0x00; // length high
    @memcpy(buffer[pos + 8 .. pos + 8 + ts_uid.len], ts_uid);
    pos += 8 + ts_uid.len;

    // Media Storage SOP Class UID (0002,0002) VR=UI
    buffer[pos] = 0x02; // group low
    buffer[pos + 1] = 0x00; // group high
    buffer[pos + 2] = 0x02; // element low
    buffer[pos + 3] = 0x00; // element high
    buffer[pos + 4] = 'U'; // VR
    buffer[pos + 5] = 'I';
    const sop_class = "1.2.840.10008.5.1.4.1.1.2";
    buffer[pos + 6] = @intCast(sop_class.len);
    buffer[pos + 7] = 0x00;
    @memcpy(buffer[pos + 8 .. pos + 8 + sop_class.len], sop_class);
    pos += 8 + sop_class.len;

    // Media Storage SOP Instance UID (0002,0003) VR=UI
    buffer[pos] = 0x02; // group low
    buffer[pos + 1] = 0x00; // group high
    buffer[pos + 2] = 0x03; // element low
    buffer[pos + 3] = 0x00; // element high
    buffer[pos + 4] = 'U'; // VR
    buffer[pos + 5] = 'I';
    const sop_instance = "1.2.3.4.5.6.7.8.9";
    buffer[pos + 6] = @intCast(sop_instance.len);
    buffer[pos + 7] = 0x00;
    @memcpy(buffer[pos + 8 .. pos + 8 + sop_instance.len], sop_instance);

    var file_meta = try FileMeta.parse(&buffer, allocator);
    defer file_meta.deinit(allocator);

    try std.testing.expectEqualStrings("DICM", &file_meta.prefix);
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            file_meta.transfer_syntax_uid.slice,
            "1.2.840.10008.1.2.1",
        ) != null,
    );
}
