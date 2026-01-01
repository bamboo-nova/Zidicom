const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Dataset = @import("parser.zig").Dataset;
const Tag = @import("data_element.zig").Tag;

/// DICOM Metadata structure for JSON export
pub const Metadata = struct {
    patient_name: ?[]const u8 = null,
    patient_id: ?[]const u8 = null,
    patient_birth_date: ?[]const u8 = null,
    patient_sex: ?[]const u8 = null,
    study_instance_uid: ?[]const u8 = null,
    study_date: ?[]const u8 = null,
    study_time: ?[]const u8 = null,
    study_description: ?[]const u8 = null,
    rows: ?u16 = null,
    columns: ?u16 = null,
    bits_allocated: ?u16 = null,
    bits_stored: ?u16 = null,
    samples_per_pixel: ?u16 = null,
    photometric_interpretation: ?[]const u8 = null,
    rescale_intercept: ?[]const u8 = null,
    rescale_slope: ?[]const u8 = null,
    window_center: ?[]const u8 = null,
    window_width: ?[]const u8 = null,

    pub fn deinit(self: *Metadata, allocator: std.mem.Allocator) void {
        if (self.patient_name) |s| allocator.free(s);
        if (self.patient_id) |s| allocator.free(s);
        if (self.patient_birth_date) |s| allocator.free(s);
        if (self.patient_sex) |s| allocator.free(s);
        if (self.study_instance_uid) |s| allocator.free(s);
        if (self.study_date) |s| allocator.free(s);
        if (self.study_time) |s| allocator.free(s);
        if (self.study_description) |s| allocator.free(s);
        if (self.photometric_interpretation) |s| allocator.free(s);
        if (self.rescale_intercept) |s| allocator.free(s);
        if (self.rescale_slope) |s| allocator.free(s);
        if (self.window_center) |s| allocator.free(s);
        if (self.window_width) |s| allocator.free(s);
    }

    /// Extract metadata from dataset
    pub fn fromDataset(dataset: Dataset, allocator: std.mem.Allocator) !Metadata {
        var meta = Metadata{};

        // Patient information
        meta.patient_name = try dataset.getValueAsString(Tag.PatientName, allocator);
        meta.patient_id = try dataset.getValueAsString(Tag.PatientID, allocator);
        meta.patient_birth_date = try dataset.getValueAsString(Tag.PatientBirthDate, allocator);
        meta.patient_sex = try dataset.getValueAsString(Tag.PatientSex, allocator);

        // Study information
        meta.study_instance_uid = try dataset.getValueAsString(Tag.StudyInstanceUID, allocator);
        meta.study_date = try dataset.getValueAsString(Tag.StudyDate, allocator);
        meta.study_time = try dataset.getValueAsString(Tag.StudyTime, allocator);
        meta.study_description = try dataset.getValueAsString(Tag.StudyDescription, allocator);

        // Image information
        meta.rows = try dataset.getValueAsU16(Tag.Rows, true);
        meta.columns = try dataset.getValueAsU16(Tag.Columns, true);
        meta.bits_allocated = try dataset.getValueAsU16(Tag.BitsAllocated, true);
        meta.bits_stored = try dataset.getValueAsU16(Tag.BitsStored, true);
        meta.samples_per_pixel = try dataset.getValueAsU16(Tag.SamplesPerPixel, true);
        meta.photometric_interpretation = try dataset.getValueAsString(Tag.PhotometricInterpretation, allocator);

        // Rescale information
        meta.rescale_intercept = try dataset.getValueAsString(Tag.RescaleIntercept, allocator);
        meta.rescale_slope = try dataset.getValueAsString(Tag.RescaleSlope, allocator);
        meta.window_center = try dataset.getValueAsString(Tag.WindowCenter, allocator);
        meta.window_width = try dataset.getValueAsString(Tag.WindowWidth, allocator);

        return meta;
    }

    /// Convert metadata to JSON string
    pub fn toJson(self: Metadata, allocator: std.mem.Allocator) ![]const u8 {
        var json_str = std.ArrayListUnmanaged(u8){};
        errdefer json_str.deinit(allocator);

        try json_str.appendSlice(allocator, "{");

        var first = true;

        // Helper to add field
        const addStringField = struct {
            fn f(arr: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, is_first: *bool, name: []const u8, value: ?[]const u8) !void {
                if (value) |v| {
                    if (!is_first.*) try arr.appendSlice(alloc, ",");
                    try arr.writer(alloc).print("\"{s}\":\"{s}\"", .{ name, v });
                    is_first.* = false;
                }
            }
        }.f;

        const addU16Field = struct {
            fn f(arr: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, is_first: *bool, name: []const u8, value: ?u16) !void {
                if (value) |v| {
                    if (!is_first.*) try arr.appendSlice(alloc, ",");
                    try arr.writer(alloc).print("\"{s}\":{d}", .{ name, v });
                    is_first.* = false;
                }
            }
        }.f;

        try addStringField(&json_str, allocator, &first, "patientName", self.patient_name);
        try addStringField(&json_str, allocator, &first, "patientId", self.patient_id);
        try addStringField(&json_str, allocator, &first, "patientBirthDate", self.patient_birth_date);
        try addStringField(&json_str, allocator, &first, "patientSex", self.patient_sex);
        try addStringField(&json_str, allocator, &first, "studyInstanceUid", self.study_instance_uid);
        try addStringField(&json_str, allocator, &first, "studyDate", self.study_date);
        try addStringField(&json_str, allocator, &first, "studyTime", self.study_time);
        try addStringField(&json_str, allocator, &first, "studyDescription", self.study_description);
        try addU16Field(&json_str, allocator, &first, "rows", self.rows);
        try addU16Field(&json_str, allocator, &first, "columns", self.columns);
        try addU16Field(&json_str, allocator, &first, "bitsAllocated", self.bits_allocated);
        try addU16Field(&json_str, allocator, &first, "bitsStored", self.bits_stored);
        try addU16Field(&json_str, allocator, &first, "samplesPerPixel", self.samples_per_pixel);
        try addStringField(&json_str, allocator, &first, "photometricInterpretation", self.photometric_interpretation);
        try addStringField(&json_str, allocator, &first, "rescaleIntercept", self.rescale_intercept);
        try addStringField(&json_str, allocator, &first, "rescaleSlope", self.rescale_slope);
        try addStringField(&json_str, allocator, &first, "windowCenter", self.window_center);
        try addStringField(&json_str, allocator, &first, "windowWidth", self.window_width);

        try json_str.appendSlice(allocator, "}");

        return json_str.toOwnedSlice(allocator);
    }
};

test "Metadata JSON conversion" {
    const allocator = std.testing.allocator;

    var meta = Metadata{
        .patient_name = try allocator.dupe(u8, "Test Patient"),
        .rows = 512,
        .columns = 512,
    };
    defer meta.deinit(allocator);

    const json = try meta.toJson(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "Test Patient") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "512") != null);
}
