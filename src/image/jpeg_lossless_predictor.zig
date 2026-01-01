const std = @import("std");

/// JPEG Lossless prediction modes (1-7)
///
/// Pixel positions:
///   C B
///   A X
///
/// Where X is the pixel to predict
/// A is left, B is above, C is above-left
pub fn predict(
    predictor: u8,
    a: i32, // Left (Ra)
    b: i32, // Above (Rb)
    c: i32, // Above-left (Rc)
) i32 {
    return switch (predictor) {
        0 => 0, // No prediction (used for first pixels)
        1 => a, // Ra (left)
        2 => b, // Rb (above)
        3 => c, // Rc (above-left)
        4 => a + b - c, // Ra + Rb - Rc
        5 => a + ((b - c) >> 1), // Ra + (Rb - Rc)/2
        6 => b + ((a - c) >> 1), // Rb + (Ra - Rc)/2
        7 => (a + b) >> 1, // (Ra + Rb)/2
        else => 0,
    };
}

/// Get predicted value for a pixel
/// image: decoded image buffer
/// x, y: pixel coordinates
/// component: color component index
/// width, height: image dimensions
/// num_components: number of color components
/// predictor: prediction mode (1-7)
/// precision: sample precision (P)
/// point_transform: point transform parameter (Pt)
pub fn getPredictedValue(
    image: []const i32,
    x: usize,
    y: usize,
    component: usize,
    width: usize,
    num_components: usize,
    predictor: u8,
    precision: u8,
    point_transform: u8,
) i32 {
    // For first pixel in first row, use 2^(P-Pt-1) where P is precision
    // For other first row pixels, use predictor 1 (left)
    // For first column pixels, use predictor 2 (above)

    // Initial predictor value: 2^(P-Pt-1)
    const shift_amount = if (precision > point_transform) precision - point_transform - 1 else 0;
    const shift_val: i32 = @as(i32, 1) << @intCast(shift_amount);

    var ra: i32 = 0; // Left
    var rb: i32 = 0; // Above
    var rc: i32 = 0; // Above-left

    // Get left pixel (Ra)
    if (x > 0) {
        const left_idx = ((y * width) + (x - 1)) * num_components + component;
        ra = image[left_idx];
    } else {
        ra = shift_val;
    }

    // Get above pixel (Rb)
    if (y > 0) {
        const above_idx = (((y - 1) * width) + x) * num_components + component;
        rb = image[above_idx];
    } else {
        rb = shift_val;
    }

    // Get above-left pixel (Rc)
    if (x > 0 and y > 0) {
        const above_left_idx = (((y - 1) * width) + (x - 1)) * num_components + component;
        rc = image[above_left_idx];
    } else {
        rc = shift_val;
    }

    // Special cases for first row and column
    if (y == 0 and x == 0) {
        // First pixel of first row
        return shift_val;
    } else if (y == 0) {
        // First row: use predictor 1 (left)
        return ra;
    } else if (x == 0) {
        // First column: use predictor 2 (above)
        return rb;
    }

    return predict(predictor, ra, rb, rc);
}

test "predictor functions" {
    // Test predictor 1 (left)
    try std.testing.expectEqual(@as(i32, 100), predict(1, 100, 200, 50));

    // Test predictor 2 (above)
    try std.testing.expectEqual(@as(i32, 200), predict(2, 100, 200, 50));

    // Test predictor 3 (above-left)
    try std.testing.expectEqual(@as(i32, 50), predict(3, 100, 200, 50));

    // Test predictor 4 (Ra + Rb - Rc)
    try std.testing.expectEqual(@as(i32, 250), predict(4, 100, 200, 50));

    // Test predictor 7 ((Ra + Rb)/2)
    try std.testing.expectEqual(@as(i32, 150), predict(7, 100, 200, 50));
}

test "getPredictedValue first pixel" {
    var image = [_]i32{0} ** 12; // 2x2 image, 3 components

    // First pixel should be 2^(P-Pt-1)
    // With P=8, Pt=0, so 2^(8-0-1) = 2^7 = 128
    const pred = getPredictedValue(&image, 0, 0, 0, 2, 3, 1, 8, 0);
    try std.testing.expectEqual(@as(i32, 128), pred);

    // With P=16, Pt=0, so 2^(16-0-1) = 2^15 = 32768
    const pred16 = getPredictedValue(&image, 0, 0, 0, 2, 3, 1, 16, 0);
    try std.testing.expectEqual(@as(i32, 32768), pred16);
}
