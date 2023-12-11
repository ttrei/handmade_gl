const std = @import("std");
const geometry = @import("geometry.zig");

const Allocator = std.mem.Allocator;

const Point = geometry.Point;

pub const Pixel = struct {
    x: i32,
    y: i32,

    pub fn fromPoint(p: Point) Pixel {
        return Pixel{ .x = @intFromFloat(p.x), .y = @intFromFloat(p.y) };
    }
};

/// 2D pixel array, row-major
pub const PixelBuffer = struct {
    is_subbuffer: bool = false,
    pixels: []u32,
    /// Position of the subbuffer origin in the parent buffer coordinate system (can be outside of the parent buffer)
    origin: Pixel = .{ .x = 0, .y = 0 },
    /// Dimensions of the subbuffer
    width: u32,
    height: u32,
    /// Coordinates (in the subbuffer coordinate system) of the visible region
    visible_topleft: Pixel,
    visible_bottomright: Pixel,
    /// How many pixels have to be skipped to go directly one row down
    stride: u32,

    pub fn init(pixels: []u32, width: u32, height: u32) !PixelBuffer {
        if (pixels.len != @as(u32, width) * height) return error.InvalidPixelBuffer;
        return .{
            .pixels = pixels,
            .width = width,
            .height = height,
            .visible_topleft = .{ .x = 0, .y = 0 },
            .visible_bottomright = .{ .x = @intCast(width), .y = @intCast(height) },
            .stride = width,
        };
    }

    pub fn subBuffer(self: *const PixelBuffer, origin: Pixel, width: u32, height: u32) ?PixelBuffer {
        if (width == 0 or height == 0) return null;
        const iwidth: i32 = @intCast(width);
        const iheight: i32 = @intCast(height);
        const iwidth_parent: i32 = @intCast(self.width);
        const iheight_parent: i32 = @intCast(self.height);
        // coordinates (in the parent buffer coordinate system) of the visible part of the subbuffer
        const left = @max(origin.x, 0);
        const top = @max(origin.y, 0);
        const right = @min(origin.x + iwidth, iwidth_parent) - 1;
        const bottom = @min(origin.y + iheight, iheight_parent) - 1;
        if (left >= self.width or top >= self.height or right < 0 or bottom < 0) return null;
        const start: u32 = @intCast(top * @as(i32, @intCast(self.stride)) + left);
        const end: u32 = @intCast(bottom * @as(i32, @intCast(self.stride)) + right);
        return PixelBuffer{
            .is_subbuffer = true,
            .pixels = self.pixels[start .. end + 1],
            .origin = origin,
            .width = width,
            .height = height,
            .visible_topleft = .{ .x = @max(-origin.x, 0), .y = @max(-origin.y, 0) },
            .visible_bottomright = .{
                .x = @min(iwidth, iwidth_parent - origin.x),
                .y = @min(iheight, iheight_parent - origin.y),
            },
            .stride = self.stride,
        };
    }

    pub fn clear(self: *PixelBuffer, color: u32) void {
        if (!self.is_subbuffer) {
            for (self.pixels) |*pixel| pixel.* = color;
            return;
        }
        var row_start_pixel_idx = self.pixelIdx(&self.visible_topleft) orelse unreachable;
        var idx = row_start_pixel_idx;
        var y = self.visible_topleft.y;
        var x = self.visible_topleft.x;
        while (y < self.visible_bottomright.y) : (y += 1) {
            while (x < self.visible_bottomright.x) : (x += 1) {
                self.pixels[idx] = color;
                idx += 1;
            }
            row_start_pixel_idx += self.stride;
            idx = row_start_pixel_idx;
            x = self.visible_topleft.x;
        }
    }

    /// Calculate index of a Pixel in the subbuffer coordinate system
    pub fn pixelIdx(self: *const PixelBuffer, p: *const Pixel) ?u32 {
        if (p.x < self.visible_topleft.x or p.y < self.visible_topleft.y) return null;
        if (p.x >= self.visible_bottomright.x or p.y >= self.visible_bottomright.y) return null;
        return @as(u32, @intCast(p.y - self.visible_topleft.y)) * self.stride + @as(u32, @intCast(p.x - self.visible_topleft.x));
    }

    pub fn pixelValue(self: *const PixelBuffer, p: *const Pixel) ?u32 {
        return self.pixels[self.pixelIdx(p) orelse return null];
    }
};

test "buffer" {
    const pixels = try std.testing.allocator.alloc(u32, 10 * 15);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, 10, 15);

    try std.testing.expectEqual(buffer.pixels.len, 10 * 15);

    var buffer2 = buffer.subBuffer(.{ .x = 0, .y = 0 }, 10, 15) orelse unreachable;
    var buffer3 = buffer.subBuffer(.{ .x = 1, .y = 1 }, 8, 13) orelse unreachable;
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

    const buffer4 = buffer2.subBuffer(.{ .x = 1, .y = 1 }, 8, 13) orelse unreachable;
    try std.testing.expectEqualSlices(u32, buffer3.pixels, buffer4.pixels);
}

test "subbuffer" {
    const white = 0xFFFFFFFF;
    const black = 0x000000FF;

    const pixels = try std.testing.allocator.alloc(u32, 10 * 15);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, 10, 15);

    buffer.clear(white);
    const buffer2 = buffer.subBuffer(.{ .x = -100, .y = -100 }, 20, 20);
    try std.testing.expectEqual(buffer2, null);

    var buffer3 = buffer.subBuffer(.{ .x = -100, .y = -100 }, 150, 150) orelse unreachable;
    try std.testing.expectEqual(buffer3.pixels.len, buffer.pixels.len);
    buffer3.clear(black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 9, .y = 14 }), black);

    buffer.clear(white);
    var buffer4 = buffer.subBuffer(.{ .x = 5, .y = 5 }, 20, 20) orelse unreachable;
    try std.testing.expect(buffer4.pixels.len < buffer.pixels.len);
    buffer4.clear(black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 9, .y = 14 }), black);

    buffer.clear(white);
    const buffer5 = buffer.subBuffer(.{ .x = 100, .y = 100 }, 20, 20);
    try std.testing.expectEqual(buffer5, null);
}
