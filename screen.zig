const std = @import("std");
const geometry = @import("geometry.zig");

const Allocator = std.mem.Allocator;

const ScreenCoordinate = i32;
const ScreenCoordinateSubPixel = f64;

// Platform-independent ScreenBuffer of pixels + code for rendering geometry primitives.
// Application code renders to the ScreenBuffer which is then displayed by platform code.

pub const Point = struct {
    x: ScreenCoordinate,
    y: ScreenCoordinate,
};

pub const PointSubPixel = struct {
    x: f64,
    y: f64,

    pub fn fromPixel(c: *const Point) PointSubPixel {
        return PointSubPixel{
            .x = @intToFloat(f64, c.x),
            .y = @intToFloat(f64, c.y),
        };
    }
};

pub const ScreenBuffer = struct {
    width: u32,
    height: u32,
    pixels: []u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, width: u32, height: u32) !ScreenBuffer {
        return ScreenBuffer{
            .width = width,
            .height = height,
            .pixels = try allocator.alloc(u32, width * height),
            .allocator = allocator,
        };
    }
    pub fn deinit(self: *const ScreenBuffer) void {
        self.allocator.free(self.pixels);
    }

    pub fn clear(self: *ScreenBuffer, color: u32) void {
        filledRectangle(
            self,
            color,
            0,
            0,
            @intCast(ScreenCoordinate, self.width),
            @intCast(ScreenCoordinate, self.height),
        );
    }
};

pub fn lineSegment(
    buffer: *ScreenBuffer,
    color: u32,
    p1: *const Point,
    p2: *const Point,
) void {
    lineSegmentSubPixel(
        buffer,
        color,
        &PointSubPixel.fromPixel(p1),
        &PointSubPixel.fromPixel(p2),
    );
}

pub fn lineSegmentSubPixel(
    buffer: *ScreenBuffer,
    color: u32,
    p1: *const PointSubPixel,
    p2: *const PointSubPixel,
) void {
    // Non-optimal implementation - invisible segments are not culled.

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = @sqrt(dx * dx + dy * dy);

    var x: ScreenCoordinate = undefined;
    var y: ScreenCoordinate = undefined;
    var t: f64 = 0;
    while (t < length) : (t += 1) {
        x = @floatToInt(ScreenCoordinate, p1.x + dx * t / length);
        y = @floatToInt(ScreenCoordinate, p1.y + dy * t / length);
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

pub fn filledCircle(buffer: *ScreenBuffer, color: u32, c: *const Point, r: u32) void {
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

pub fn triangle(
    buffer: *ScreenBuffer,
    color: u32,
    p1: *const Point,
    p2: *const Point,
    p3: *const Point,
) void {
    lineSegment(buffer, color, p1, p2);
    lineSegment(buffer, color, p2, p3);
    lineSegment(buffer, color, p3, p1);
}

pub fn triangleSubPixel(
    buffer: *ScreenBuffer,
    color: u32,
    p1: *const PointSubPixel,
    p2: *const PointSubPixel,
    p3: *const PointSubPixel,
) void {
    lineSegmentSubPixel(buffer, color, p1, p2);
    lineSegmentSubPixel(buffer, color, p2, p3);
    lineSegmentSubPixel(buffer, color, p3, p1);
}

pub fn polygonToPoints(allocator: Allocator, poly: *const geometry.Polygon) ![]Point {
    var buf = try allocator.alloc(Point, poly.n);
    var i: usize = 0;
    var v = poly.first;
    while (i < poly.n) : (i += 1) {
        buf[i] = Point{ .x = v.p.x, .y = v.p.y };
        v = v.next;
    }
    return buf;
}

pub fn polygonFromPoints(
    buffer: *ScreenBuffer,
    color: u32,
    points: []const Point,
) void {
    var idx2: usize = undefined;
    for (points) |_, idx| {
        idx2 = (idx + 1) % points.len;
        lineSegment(buffer, color, &points[idx], &points[idx2]);
    }
}

pub fn polygonFromSubPixelPoints(
    buffer: *ScreenBuffer,
    color: u32,
    points: []const PointSubPixel,
) void {
    var idx2: usize = undefined;
    for (points) |_, idx| {
        idx2 = (idx + 1) % points.len;
        lineSegmentSubPixel(buffer, color, &points[idx], &points[idx2]);
    }
}
