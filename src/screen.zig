const std = @import("std");
const geometry = @import("geometry.zig");

const Allocator = std.mem.Allocator;

const PointFloat = geometry.PointFloat;

pub const ScreenCoordinate = u32;

pub const Pixel = struct {
    x: ScreenCoordinate,
    y: ScreenCoordinate,

    pub fn fromPointFloat(p: *const PointFloat) ?Pixel {
        if (p.x < 0 or p.y < 0) return null;
        return Pixel{
            .x = @as(ScreenCoordinate, @intFromFloat(p.x)),
            .y = @as(ScreenCoordinate, @intFromFloat(p.y)),
        };
    }
};

// 2D pixel array, row-major
pub const PixelBuffer = struct {
    pixels: []u32,
    // Dimensions of the subset
    width: ScreenCoordinate,
    height: ScreenCoordinate,
    // How many pixels have to be skipped to go directly one row down
    stride: ScreenCoordinate,
    const Self = @This();

    // Initialize to the subset containing the whole array
    pub fn init(pixels: []u32, width: ScreenCoordinate, height: ScreenCoordinate) !Self {
        if (pixels.len != @as(u32, width) * height) {
            return error.InvalidPixelBuffer;
        }
        return Self{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = width,
        };
    }

    pub fn subBuffer(
        self: *const Self,
        width: ScreenCoordinate,
        height: ScreenCoordinate,
        origin: Pixel,
    ) !Self {
        if (width < 1 or height < 1) return error.InvalidPixelBuffer;
        if (origin.x + width > self.width or origin.y + height > self.height) {
            return error.InvalidPixelBuffer;
        }
        const start = origin.y * self.stride + origin.x;
        return Self{
            .pixels = self.pixels[start .. start + (height - 1) * self.stride + width],
            .width = width,
            .height = height,
            .stride = self.stride,
        };
    }

    pub fn clear(self: *Self, color: u32) void {
        var y: ScreenCoordinate = 0;
        while (y < self.height) : (y += 1) {
            var x: ScreenCoordinate = 0;
            while (x < self.width) : (x += 1) {
                self.pixels[y * self.stride + x] = color;
            }
        }
    }

    // Calculate index of a Pixel, given coordinates relative to the subbuffer origin
    pub fn pixelIdx(self: *const Self, p: *const Pixel) ?u32 {
        if (p.x >= self.width or p.y >= self.height) return null;
        return p.y * self.stride + p.x;
    }

    pub fn pixelValue(self: *const Self, p: *const Pixel) ?u32 {
        return self.pixels[self.pixelIdx(p) orelse return null];
    }
};

test "buffer" {
    const pixels = try std.testing.allocator.alloc(u32, 10 * 15);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, 10, 15);

    try std.testing.expectEqual(buffer.pixels.len, 10 * 15);

    var buffer2 = try buffer.subBuffer(10, 15, .{ .x = 0, .y = 0 });
    var buffer3 = try buffer.subBuffer(8, 13, .{ .x = 1, .y = 1 });
    try std.testing.expectEqualSlices(u32, buffer.pixels, buffer2.pixels);

    const white = 0xFFFFFFFF;
    const black = 0x000000FF;
    const red = 0xFF0000FF;

    buffer.clear(white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer3.pixelValue(&.{ .x = 0, .y = 0 }), white);

    buffer2.clear(black);
    buffer3.clear(red);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), black);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 0, .y = 0 }), black);
    try std.testing.expectEqual(buffer3.pixelValue(&.{ .x = 0, .y = 0 }), red);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 1, .y = 1 }), red);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 9, .y = 14 }), black);

    try std.testing.expectEqualSlices(u32, buffer.pixels, buffer2.pixels);

    const buffer4 = try buffer2.subBuffer(8, 13, .{ .x = 1, .y = 1 });
    try std.testing.expectEqualSlices(u32, buffer3.pixels, buffer4.pixels);
}
