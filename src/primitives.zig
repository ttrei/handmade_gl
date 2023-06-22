const std = @import("std");
const screen = @import("screen.zig");
const ScreenBuffer = screen.ScreenBuffer;

const Pixel = screen.Pixel;
const SubPixel = screen.SubPixel;
const ScreenCoordinate = screen.ScreenCoordinate;
const ScreenCoordinateSubPixel = screen.ScreenCoordinateSubPixel;

pub fn lineSegment(
    buffer: *ScreenBuffer,
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
    buffer: *ScreenBuffer,
    color: u32,
    p1: *const SubPixel,
    p2: *const SubPixel,
) void {
    // Non-optimal implementation - invisible segments are not culled.

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = @sqrt(dx * dx + dy * dy);

    var x: ScreenCoordinate = undefined;
    var y: ScreenCoordinate = undefined;
    var t: f64 = 0;
    while (t < length) : (t += 1) {
        x = @intFromFloat(ScreenCoordinate, p1.x + dx * t / length);
        y = @intFromFloat(ScreenCoordinate, p1.y + dy * t / length);
        if (x < 0 or x >= buffer.width or y < 0 or y >= buffer.height) continue;
        buffer.pixels[@intCast(u32, y) * buffer.width + @intCast(u32, x)] = color;
    }
}

pub fn filledRectangle(
    buffer: *ScreenBuffer,
    color: u32,
    left: ScreenCoordinate,
    top: ScreenCoordinate,
    right: ScreenCoordinate,
    bottom: ScreenCoordinate,
) void {
    if (left >= buffer.width or right <= 0 or top >= buffer.height or bottom <= 0) return;
    const clamped_left: u32 = if (left < 0) 0 else @intCast(u32, left);
    const clamped_top: u32 = if (top < 0) 0 else @intCast(u32, top);
    const clamped_right: u32 = if (right > buffer.width) buffer.width else @intCast(u32, right);
    const clamped_bottom: u32 = if (bottom > buffer.height) buffer.height else @intCast(u32, bottom);
    var row_start: u32 = buffer.width * clamped_top + clamped_left;
    var y: u32 = 0;
    const height = clamped_bottom - clamped_top;
    while (y < height) : (y += 1) {
        const width = clamped_right - clamped_left;
        var x: u32 = 0;
        while (x < width) : (x += 1) buffer.pixels[row_start + x] = color;
        row_start += buffer.width;
    }
}

pub fn filledCircle(buffer: *ScreenBuffer, color: u32, c: *const Pixel, r: u32) void {
    const r_i32 = @intCast(i32, r);
    if (c.x - r_i32 >= buffer.width or c.x + r_i32 <= 0 or c.y - r_i32 >= buffer.height or c.y + r_i32 <= 0) return;
    const ymin = if (c.y - r_i32 < 0) 0 else c.y - r_i32;
    const ymax = if (c.y + r_i32 > buffer.height) @intCast(ScreenCoordinate, buffer.height) else c.y + r_i32;

    var y: ScreenCoordinate = ymin;
    while (y < ymax) : (y += 1) {
        const dy = std.math.absCast(c.y - y);
        const dx = std.math.sqrt(r * r - dy * dy);
        if (c.x - dx >= buffer.width or c.x + dx <= 0) continue;
        const xmin = if (c.x - dx < 0) 0 else c.x - dx;
        const xmax = if (c.x + dx > buffer.width) @intCast(ScreenCoordinate, buffer.width) else c.x + dx;
        const row_start = buffer.width * @intCast(u32, y);
        var x: ScreenCoordinate = xmin;
        while (x < xmax) : (x += 1) buffer.pixels[row_start + @intCast(u32, x)] = color;
    }
}
