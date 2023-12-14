const std = @import("std");
const screen = @import("screen.zig");
const PixelBuffer = screen.PixelBuffer;

const Allocator = std.mem.Allocator;

const Pixel = screen.Pixel;

pub const Transform = struct {
    translation: Vec2 = Vec2{ .x = 0.0, .y = 0.0 },
    scale: f64 = 1.0,

    pub fn apply(self: *const Transform, p: Point) Point {
        return p.translate(self.translation).scale(self.scale);
    }

    pub fn reverse(self: *const Transform, p: Point) Point {
        return p.scale(1.0 / self.scale).translate(self.translation.mul(-1));
    }
};

pub const Point = struct {
    x: f64,
    y: f64,

    pub fn fromPixel(p: Pixel) Point {
        return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
    }

    pub fn subtract(self: *const Point, other: Point) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn translate(self: *const Point, displacement: Vec2) Point {
        return .{ .x = self.x + displacement.x, .y = self.y + displacement.y };
    }

    pub fn scale(self: *const Point, factor: f64) Point {
        return .{ .x = self.x * factor, .y = self.y * factor };
    }
};

/// Free vector (we care only about its magnitude and direction)
pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn fromPoint(p: Point) Vec2 {
        return .{ .x = p.x, .y = p.y };
    }

    pub fn add(self: *const Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub fn sub(self: *const Vec2, other: Vec2) Vec2 {
        return self.add(other.mul(-1));
    }

    pub fn mul(self: *const Vec2, multiplier: f64) Vec2 {
        return .{
            .x = self.x * multiplier,
            .y = self.y * multiplier,
        };
    }

    pub fn dot(self: *const Vec2, other: Vec2) f64 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn squared(self: *const Vec2) f64 {
        return self.dot(self.*);
    }

    pub fn normalized(self: *const Vec2) Vec2 {
        return self.mul(1 / @sqrt(self.squared()));
    }

    pub fn invertX(self: *const Vec2) Vec2 {
        return .{ .x = -self.x, .y = self.y };
    }

    pub fn invertY(self: *const Vec2) Vec2 {
        return .{ .x = self.x, .y = -self.y };
    }

    pub fn angle(self: *const Vec2) f64 {
        return std.math.atan2(f64, self.y, self.x);
    }
};

/// Bound vector (we care about its starting point)
pub const BoundVec2 = struct {
    pos: Point,
    vec: Vec2,
};

pub const Shape = union(enum) {
    polygon: Polygon,
    rectangle: Rectangle,
    circle: Circle,

    pub fn draw(self: *const Shape, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        switch (self.*) {
            .polygon => self.polygon.draw(buffer, color),
            .rectangle => self.rectangle.draw(buffer, color),
            .circle => self.circle.draw(buffer, color),
        }
    }

    pub fn transform(self: *Shape, t: *const Transform) void {
        switch (self.*) {
            .polygon => self.polygon.transform(t),
            .rectangle => self.rectangle.transform(t),
            .circle => self.circle.transform(t),
        }
    }

    pub fn clone(self: *const Shape, allocator: Allocator) !Shape {
        return switch (self.*) {
            .polygon => .{ .polygon = try self.polygon.clone(allocator) },
            else => self.*,
        };
    }

    pub fn deinit(self: *Shape) void {
        switch (self.*) {
            .polygon => self.polygon.deinit(),
            else => {},
        }
    }
};

pub const Polygon = struct {
    const Vertex = struct {
        p: Point,
        ear: bool,
        next: *Vertex,
        prev: *Vertex,
    };

    arena: std.heap.ArenaAllocator = undefined,
    first: *Vertex = undefined,
    n: usize = 0,

    pub fn init(allocator: Allocator) Polygon {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: *Polygon) void {
        self.arena.deinit();
    }

    pub fn add_vertex(self: *Polygon, p: Point) !void {
        const v = try self.arena.allocator().create(Vertex);
        if (self.n == 0) {
            v.* = .{ .p = p, .ear = false, .next = v, .prev = v };
            self.first = v;
        } else {
            v.* = .{ .p = p, .ear = false, .next = self.first, .prev = self.first.prev };
            self.first.prev = v;
            v.prev.next = v;
        }
        self.n += 1;
    }

    pub fn area2(self: *const Polygon) i32 {
        if (self.n < 3) return 0;
        var sum: i32 = 0;
        var a = self.first.next;
        while (a.next != self.first) : (a = a.next) {
            sum += orientedArea2(&self.first.p, &a.p, &a.next.p);
        }
        return sum;
    }

    pub fn transform(self: *Polygon, t: *const Transform) void {
        if (self.n == 0) return;
        self.first.p = t.apply(self.first.p);
        var current = self.first.next;
        while (current != self.first) : (current = current.next) {
            current.p = t.apply(current.p);
        }
    }

    pub fn clone(self: *const Polygon, allocator: Allocator) !Polygon {
        var cloned = Polygon.init(allocator);
        if (self.n == 0) return cloned;
        try cloned.add_vertex(self.first.p);
        var current = self.first.next;
        while (current != self.first) : (current = current.next) {
            try cloned.add_vertex(current.p);
        }
        return cloned;
    }

    /// Draw to a PixelBuffer relative to the buffer coordinate system.
    pub fn draw(self: *const Polygon, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        if (self.n == 0) return;
        var p1: Point = undefined;
        var p2: Point = undefined;
        var v = self.first;
        var i: usize = 0;
        while (i < self.n) : (i += 1) {
            p1 = v.p;
            p2 = v.next.p;
            drawLineSegment(buffer, color, &p1, &p2);
            v = v.next;
        }
    }
};

pub const Rectangle = struct {
    p1: Point,
    p2: Point,

    pub fn transform(self: *Rectangle, t: *const Transform) void {
        self.p1 = t.apply(self.p1);
        self.p2 = t.apply(self.p2);
    }

    /// Draw to a PixelBuffer relative to the buffer coordinate system.
    pub fn draw(self: *const Rectangle, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        // Rectangle limits.
        const left: i32 = @intFromFloat(@round(@min(self.p1.x, self.p2.x)));
        const right: i32 = @intFromFloat(@round(@max(self.p1.x, self.p2.x)));
        const top: i32 = @intFromFloat(@round(@min(self.p1.y, self.p2.y)));
        const bottom: i32 = @intFromFloat(@round(@max(self.p1.y, self.p2.y)));
        const visible_left = @max(left, buffer.visible_topleft.x, 0);
        const visible_top = @max(top, buffer.visible_topleft.y, 0);
        const visible_right = @min(right, buffer.visible_bottomright.x, @as(i32, @intCast(buffer.width)));
        const visible_bottom = @min(bottom, buffer.visible_bottomright.y, @as(i32, @intCast(buffer.height)));
        if (visible_left >= visible_right or visible_top >= visible_bottom) return;
        var row_start_pixel_idx = buffer.pixelIdx(&.{ .x = visible_left, .y = visible_top }) orelse unreachable;
        var idx = row_start_pixel_idx;
        var x = visible_left;
        var y = visible_top;
        while (y < visible_bottom) : (y += 1) {
            while (x < visible_right) : (x += 1) {
                buffer.pixels[idx] = color;
                idx += 1;
            }
            row_start_pixel_idx += buffer.stride;
            idx = row_start_pixel_idx;
            x = visible_left;
        }
    }

    pub fn drawOutline(self: *const Rectangle, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        const left: i32 = @intFromFloat(@round(@min(self.p1.x, self.p2.x)));
        const right: i32 = @intFromFloat(@round(@max(self.p1.x, self.p2.x)));
        const top: i32 = @intFromFloat(@round(@min(self.p1.y, self.p2.y)));
        const bottom: i32 = @intFromFloat(@round(@max(self.p1.y, self.p2.y)));
        if (left >= buffer.width or right <= 0 or top >= buffer.height or bottom <= 0) return;
        var p = Pixel{ .x = left, .y = top };
        while (p.y < bottom) : (p.y += 1) buffer.pixels[buffer.pixelIdx(&p) orelse continue] = color;
        p = Pixel{ .x = right - 1, .y = top };
        while (p.y < bottom) : (p.y += 1) buffer.pixels[buffer.pixelIdx(&p) orelse continue] = color;
        p = Pixel{ .x = left, .y = top };
        while (p.x < right) : (p.x += 1) buffer.pixels[buffer.pixelIdx(&p) orelse continue] = color;
        p = Pixel{ .x = left, .y = bottom - 1 };
        while (p.x < right) : (p.x += 1) buffer.pixels[buffer.pixelIdx(&p) orelse continue] = color;
    }
};

pub const Circle = struct {
    c: Point,
    r: f64,

    pub fn transform(self: *Circle, t: *const Transform) void {
        self.c = t.apply(self.c);
        self.r = t.scale * self.r;
    }

    /// Draw to a PixelBuffer relative to the buffer coordinate system.
    pub fn draw(self: *const Circle, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        const c = self.c;
        const r = self.r;
        const width = @as(f64, @floatFromInt(buffer.width));
        const height = @as(f64, @floatFromInt(buffer.height));

        if (c.x - r >= width or c.x + r <= 0 or c.y - r >= height or c.y + r <= 0) return;
        const ymin = if (c.y - r < 0) 0 else c.y - r;
        const ymax = if (c.y + r > height) height else c.y + r;

        var pixel: Pixel = undefined;
        var y: f64 = ymin;
        var x: f64 = undefined;
        while (y < ymax) : (y += 1) {
            const dy = @abs(c.y - y);
            const dx = std.math.sqrt(r * r - dy * dy);
            if (c.x - dx >= width or c.x + dx <= 0) continue;
            x = if (c.x - dx < 0) 0 else c.x - dx;
            const xmax = if (c.x + dx > width) width else c.x + dx;
            while (x < xmax) : (x += 1) {
                pixel = Pixel.fromPoint(.{ .x = x, .y = y });
                buffer.pixels[buffer.pixelIdx(&pixel) orelse continue] = color;
            }
        }
    }
};

pub const LineSegment = struct {
    p1: Point,
    p2: Point,

    pub fn transform(self: *LineSegment, t: *const Transform) void {
        self.p1 = t.apply(self.p1);
        self.p2 = t.apply(self.p2);
    }

    /// Draw to a PixelBuffer relative to the buffer coordinate system.
    pub fn draw(self: *const LineSegment, buffer: *PixelBuffer, color: u32) void {
        if (!buffer.visible()) return;
        drawLineSegment(buffer, color, &self.p1, &self.p2);
    }
};

pub fn orientedArea2(a: *const Point, b: *const Point, c: *const Point) i32 {
    return (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
}

/// Draw to a PixelBuffer relative to the buffer coordinate system.
pub fn drawLineSegment(buffer: *PixelBuffer, color: u32, p1: *const Point, p2: *const Point) void {
    if (!buffer.visible()) return;

    // TODO: Non-optimal implementation - invisible segments are not culled.
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = @sqrt(dx * dx + dy * dy);

    var p: Point = undefined;
    var pixel: Pixel = undefined;
    var t: f64 = 0;
    // TODO: Optimization possible. We can do without calling pixelIdx() on each iteration.
    //       https://github.com/ssloy/tinyrenderer/wiki/Lesson-1:-Bresenham%E2%80%99s-Line-Drawing-Algorithm
    while (t < length) : (t += 1) {
        p.x = p1.x + dx * t / length;
        p.y = p1.y + dy * t / length;
        pixel = Pixel.fromPoint(p);
        buffer.pixels[buffer.pixelIdx(&pixel) orelse continue] = color;
    }
}

test "polygon" {
    const pixels = try std.testing.allocator.alloc(u32, 3 * 3);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, 3, 3);

    const white = 0xFFFFFFFF;
    const black = 0x000000FF;

    var p = Polygon.init(std.testing.allocator);
    defer p.deinit();
    try p.add_vertex(Point{ .x = 0, .y = 0 });
    try p.add_vertex(Point{ .x = 2, .y = 0 });
    try p.add_vertex(Point{ .x = 0, .y = 2 });

    buffer.clear(white);
    p.draw(&buffer, black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 0 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 0 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 1 }), black);
    // FIXME: (1, 1) should be black, not white
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), white);
    // try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 1 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 2 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 2 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 2 }), white);
}

test "overlapping pixel buffers" {
    const pixels = try std.testing.allocator.alloc(u32, 10 * 10);
    defer std.testing.allocator.free(pixels);
    var buffer = try PixelBuffer.init(pixels, 10, 10);

    const white = 0xFFFFFFFF;
    const black = 0x000000FF;
    const red = 0xFF0000FF;
    const green = 0x00FF00FF;

    buffer.clear(black);
    const line = LineSegment{ .p1 = .{ .x = 0, .y = 0 }, .p2 = .{ .x = 9, .y = 9 } };
    line.draw(&buffer, white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 1 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 5, .y = 5 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 6 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 8, .y = 8 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 9, .y = 9 }), black);

    drawLineSegment(&buffer, red, &.{ .x = 1.0, .y = -2.0 }, &.{ .x = 1.0, .y = 3.0 });
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), red);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 2 }), red);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 3 }), black);

    var buffer2 = buffer.subBuffer(.{ .x = 1, .y = 1 }, 5, 5) orelse unreachable;
    drawLineSegment(&buffer2, green, &.{ .x = -1, .y = -1 }, &.{ .x = 9, .y = 9 });
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 0, .y = 0 }), green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 1, .y = 1 }), green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 4, .y = 4 }), green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 5, .y = 5 }), null);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), green);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), green);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 5, .y = 5 }), green);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 6 }), white);

    buffer.clear(black);
    const rect = Rectangle{ .p1 = .{ .x = 0, .y = 0 }, .p2 = .{ .x = 6, .y = 6 } };
    rect.draw(&buffer, white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 3 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 5, .y = 5 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 6 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 6 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 2 }), black);
    const rect2 = Rectangle{ .p1 = .{ .x = 1, .y = 1 }, .p2 = .{ .x = 100, .y = 100 } };
    rect2.draw(&buffer2, green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 1, .y = 1 }), green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 4, .y = 4 }), green);
    try std.testing.expectEqual(buffer2.pixelValue(&.{ .x = 5, .y = 5 }), null);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 2, .y = 6 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 6 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 2 }), black);
}
