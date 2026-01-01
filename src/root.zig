//! DICOM Viewer Library
//! Provides functionality to parse DICOM medical images and convert them to JPEG/PNG
const std = @import("std");

// Export DICOM modules
pub const vr = @import("dicom/vr.zig");
pub const data_element = @import("dicom/data_element.zig");
pub const transfer_syntax = @import("dicom/transfer_syntax.zig");
pub const file_meta = @import("dicom/file_meta.zig");
pub const parser = @import("dicom/parser.zig");
pub const metadata = @import("dicom/metadata.zig");
pub const pixel_data = @import("dicom/pixel_data.zig");
pub const encapsulated = @import("dicom/encapsulated.zig");

// Export image modules
pub const converter = @import("image/converter.zig");

// Export utility modules
pub const errors = @import("utils/errors.zig");
pub const byte_reader = @import("utils/byte_reader.zig");

// Export WASM modules
pub const wasm_allocator = @import("wasm/allocator.zig");
pub const wasm_memory = @import("wasm/memory.zig");

// Re-export common types
pub const VR = vr.VR;
pub const Tag = data_element.Tag;
pub const DataElement = data_element.DataElement;
pub const TransferSyntax = transfer_syntax.TransferSyntax;
pub const FileMeta = file_meta.FileMeta;
pub const Parser = parser.Parser;
pub const Dataset = parser.Dataset;
pub const Metadata = metadata.Metadata;
pub const PixelData = pixel_data.PixelData;
pub const ByteReader = byte_reader.ByteReader;
pub const DicomError = errors.DicomError;

test "DICOM library" {
    // Run all sub-module tests
    std.testing.refAllDecls(@This());
}
