const std = @import("std");
const VR = @import("vr.zig").VR;

/// DICOM Tag (Group, Element)
pub const Tag = packed struct {
    element: u16,
    group: u16,

    /// Create a tag from group and element numbers
    pub fn init(group: u16, element: u16) Tag {
        return .{ .group = group, .element = element };
    }

    /// Check if two tags are equal
    pub fn eql(self: Tag, other: Tag) bool {
        return self.group == other.group and self.element == other.element;
    }

    /// Format tag as (GGGG,EEEE)
    pub fn format(
        self: Tag,
        writer: anytype,
    ) !void {
        try writer.print(
            "({X:0>4},{X:0>4})",
            .{ self.group, self.element },
        );
    }

    /// Common DICOM tags
    pub const TransferSyntaxUID = Tag.init(0x0002, 0x0010);
    pub const MediaStorageSOPClassUID = Tag.init(0x0002, 0x0002);
    pub const MediaStorageSOPInstanceUID = Tag.init(0x0002, 0x0003);
    pub const ImplementationClassUID = Tag.init(0x0002, 0x0012);
    pub const FileMetaInformationGroupLength = Tag.init(0x0002, 0x0000);

    // Image-related tags
    pub const PixelData = Tag.init(0x7FE0, 0x0010);
    pub const Rows = Tag.init(0x0028, 0x0010);
    pub const Columns = Tag.init(0x0028, 0x0011);
    pub const BitsAllocated = Tag.init(0x0028, 0x0100);
    pub const BitsStored = Tag.init(0x0028, 0x0101);
    pub const HighBit = Tag.init(0x0028, 0x0102);
    pub const PixelRepresentation = Tag.init(0x0028, 0x0103);
    pub const SamplesPerPixel = Tag.init(0x0028, 0x0002);
    pub const PhotometricInterpretation = Tag.init(0x0028, 0x0004);
    pub const PlanarConfiguration = Tag.init(0x0028, 0x0006);

    // Rescale tags
    pub const RescaleIntercept = Tag.init(0x0028, 0x1052);
    pub const RescaleSlope = Tag.init(0x0028, 0x1053);
    pub const WindowCenter = Tag.init(0x0028, 0x1050);
    pub const WindowWidth = Tag.init(0x0028, 0x1051);

    // Patient tags
    pub const PatientName = Tag.init(0x0010, 0x0010);
    pub const PatientID = Tag.init(0x0010, 0x0020);
    pub const PatientBirthDate = Tag.init(0x0010, 0x0030);
    pub const PatientSex = Tag.init(0x0010, 0x0040);

    // Study tags
    pub const StudyInstanceUID = Tag.init(0x0020, 0x000D);
    pub const StudyDate = Tag.init(0x0008, 0x0020);
    pub const StudyTime = Tag.init(0x0008, 0x0030);
    pub const StudyDescription = Tag.init(0x0008, 0x1030);
};

/// DICOM Data Element
pub const DataElement = struct {
    tag: Tag,
    vr: VR,
    value_length: u32,
    value_offset: usize, // Offset in the original buffer

    /// Get the value as a byte slice from the original buffer
    pub fn getValue(self: DataElement, buffer: []const u8) ![]const u8 {
        if (self.value_offset + self.value_length > buffer.len) {
            return error.InvalidLength;
        }
        return buffer[self.value_offset .. self.value_offset + self.value_length];
    }

    /// Get the value as a string (trimmed of padding)
    pub fn getValueAsString(self: DataElement, buffer: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        const raw = try self.getValue(buffer);
        // DICOM strings are often padded with spaces or null bytes
        const trimmed = std.mem.trim(u8, raw, &[_]u8{ ' ', 0 });
        const result = try allocator.alloc(u8, trimmed.len);
        @memcpy(result, trimmed);
        return result;
    }

    /// Get the value as u16
    pub fn getValueAsU16(self: DataElement, buffer: []const u8, is_little_endian: bool) !u16 {
        const bytes = try self.getValue(buffer);
        if (bytes.len < 2) {
            return error.InvalidLength;
        }
        if (is_little_endian) {
            return std.mem.readInt(u16, bytes[0..2], .little);
        } else {
            return std.mem.readInt(u16, bytes[0..2], .big);
        }
    }

    /// Get the value as u32
    pub fn getValueAsU32(self: DataElement, buffer: []const u8, is_little_endian: bool) !u32 {
        const bytes = try self.getValue(buffer);
        if (bytes.len < 4) {
            return error.InvalidLength;
        }
        if (is_little_endian) {
            return std.mem.readInt(u32, bytes[0..4], .little);
        } else {
            return std.mem.readInt(u32, bytes[0..4], .big);
        }
    }
};

test "Tag creation and equality" {
    const tag1 = Tag.init(0x0002, 0x0010);
    const tag2 = Tag.TransferSyntaxUID;
    const tag3 = Tag.init(0x0010, 0x0010);

    try std.testing.expect(tag1.eql(tag2));
    try std.testing.expect(!tag1.eql(tag3));
}

test "Tag format" {
    const tag = Tag.init(0x0002, 0x0010);
    var buf: [128]u8 = undefined;
    const str = try std.fmt.bufPrint(&buf, "{f}", .{tag});
    try std.testing.expectEqualStrings("(0002,0010)", str);
}

test "DataElement getValue" {
    const buffer = "Hello, DICOM!";
    const elem = DataElement{
        .tag = Tag.init(0x0010, 0x0010),
        .vr = VR.LO,
        .value_length = 5,
        .value_offset = 0,
    };

    const value = try elem.getValue(buffer);
    try std.testing.expectEqualStrings("Hello", value);
}
