const std = @import("std");
const screen = @import("screen.zig");
const PixelBuffer = screen.PixelBuffer;

const Pixel = screen.Pixel;
const SubPixel = screen.SubPixel;
const ScreenCoordinate = screen.ScreenCoordinate;
const ScreenCoordinateSubPixel = screen.ScreenCoordinateSubPixel;

pub fn lineSegment(
    buffer: *PixelBuffer,
    color: u32,
    p1: *const Pixel,
    p2: *const Pixel,
) void {
    lineSegmentSubPixel(
        buffer,
        color,
        &SubPixel.fromPixel(p1),
        &SubPixel.fromPixel(p2),
    );
}

pub fn lineSegmentSubPixel(
    buffer: *PixelBuffer,
    color: u32,
    p1: *const SubPixel,
    p2: *const SubPixel,
) void {
    // Non-optimal implementation - invisible segments are not culled.

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = @sqrt(dx * dx + dy * dy);

    var p: Pixel = undefined;
    var t: f64 = 0;
    while (t < length) : (t += 1) {
        p.x = @as(ScreenCoordinate, @intFromFloat(p1.x + dx * t / length));
        p.y = @as(ScreenCoordinate, @intFromFloat(p1.y + dy * t / length));
        buffer.pixels[buffer.pixelIdx(p.sub(buffer.origin)) orelse continue] = color;
    }
}

pub fn filledRectangle(
    buffer: *PixelBuffer,
    color: u32,
    left: ScreenCoordinate,
    top: ScreenCoordinate,
    right: ScreenCoordinate,
    bottom: ScreenCoordinate,
) void {
    if (left >= buffer.width or right <= 0 or top >= buffer.height or bottom <= 0) return;
    const clamped_left: u32 = if (left < 0) 0 else @as(u32, @intCast(left));
    const clamped_top: u32 = if (top < 0) 0 else @as(u32, @intCast(top));
    const clamped_right: u32 = if (right > buffer.width) buffer.width else @as(u32, @intCast(right));
    const clamped_bottom: u32 = if (bottom > buffer.height) buffer.height else @as(u32, @intCast(bottom));
    var row_start: u32 = buffer.width * clamped_top + clamped_left;
    var y: u32 = 0;
    const height = clamped_bottom - clamped_top;
    while (y < height) : (y += 1) {
        const width = clamped_right - clamped_left;
        var x: u32 = 0;
        // TODO Use pixelIdx()
        while (x < width) : (x += 1) buffer.pixels[row_start + x] = color;
        row_start += buffer.width;
    }
}

pub fn filledCircle(buffer: *PixelBuffer, color: u32, c: *const Pixel, r: u32) void {
    const r_i32 = @as(i32, @intCast(r));
    if (c.x - r_i32 >= buffer.width or c.x + r_i32 <= 0 or c.y - r_i32 >= buffer.height or c.y + r_i32 <= 0) return;
    const ymin = if (c.y - r_i32 < 0) 0 else c.y - r_i32;
    const ymax = if (c.y + r_i32 > buffer.height) @as(ScreenCoordinate, @intCast(buffer.height)) else c.y + r_i32;

    var y: ScreenCoordinate = ymin;
    while (y < ymax) : (y += 1) {
        const dy = std.math.absCast(c.y - y);
        const dx = std.math.sqrt(r * r - dy * dy);
        if (c.x - dx >= buffer.width or c.x + dx <= 0) continue;
        const xmin = if (c.x - dx < 0) 0 else c.x - dx;
        const xmax = if (c.x + dx > buffer.width) @as(ScreenCoordinate, @intCast(buffer.width)) else c.x + dx;
        const row_start = buffer.width * @as(u32, @intCast(y));
        var x: ScreenCoordinate = xmin;
        // TODO Use pixelIdx()
        while (x < xmax) : (x += 1) buffer.pixels[row_start + @as(u32, @intCast(x))] = color;
    }
}

test "line segment" {
    const width = 800;
    const height = 600;
    const black = 0x000000ff;
    const white = 0xffffffff;
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, width, height);
    buffer.clear(black);

    lineSegment(&buffer, white, &.{ .x = 10, .y = 10 }, &.{ .x = 50, .y = 50 });
    try std.testing.expect(buffer.pixels[buffer.pixelIdx(.{ .x = 9, .y = 9 }).?] == black);
    try std.testing.expect(buffer.pixels[buffer.pixelIdx(.{ .x = 11, .y = 11 }).?] == white);
}
