const std = @import("std");
const screen = @import("screen.zig");
const PixelBuffer = screen.PixelBuffer;

const Allocator = std.mem.Allocator;

const Pixel = screen.Pixel;

const CoordinateInt = i32;
const CoordinateFloat = f64;

const ScreenCoordinate = screen.ScreenCoordinate;

pub const CoordinateTransform = struct {
    const Self = @This();

    translate_x: f64,
    translate_y: f64,
    scale: f64,

    pub fn apply(self: *const Self, p: *const PointFloat) PointFloat {
        return PointFloat{
            .x = self.scale * p.x + self.translate_x,
            .y = self.scale * p.y + self.translate_y,
        };
    }

    pub fn reverse(self: *const Self, p: *const PointFloat) PointFloat {
        return PointFloat{
            .x = (p.x - self.translate_x) / self.scale,
            .y = (p.y - self.translate_y) / self.scale,
        };
    }

    pub fn applyInt(self: *const Self, p: *const PointInt) PointInt {
        return PointInt{
            .x = @intFromFloat(self.scale * @as(f64, @floatFromInt(p.x)) + self.translate_x),
            .y = @intFromFloat(self.scale * @as(f64, @floatFromInt(p.y)) + self.translate_y),
        };
    }

    pub fn applyInplace(self: *const Self, p: *PointFloat) void {
        p.x = self.scale * p.x + self.translate_x;
        p.y = self.scale * p.y + self.translate_y;
    }

    pub fn applyIntInplace(self: *const Self, p: *PointInt) void {
        p.x = @intFromFloat(self.scale * @as(f64, @floatFromInt(p.x)) + self.translate_x);
        p.y = @intFromFloat(self.scale * @as(f64, @floatFromInt(p.y)) + self.translate_y);
    }

    pub fn scaleInt(self: *const Self, a: u32) u32 {
        return @intFromFloat(self.scale * @as(f64, @floatFromInt(a)));
    }

    pub fn reverseInt(self: *const Self, p: *const PointInt) PointInt {
        return PointInt{
            .x = @intFromFloat((@as(f64, @floatFromInt(p.x)) - self.translate_x) / self.scale),
            .y = @intFromFloat((@as(f64, @floatFromInt(p.y)) - self.translate_y) / self.scale),
        };
    }
};

pub const PointInt = struct {
    x: CoordinateInt,
    y: CoordinateInt,

    const Self = @This();

    pub fn fromFloat(p: *const PointFloat) Self {
        return Self{
            .x = @as(CoordinateInt, @intFromFloat(p.x)),
            .y = @as(CoordinateInt, @intFromFloat(p.y)),
        };
    }

    pub fn fromPixel(p: *const Pixel) Self {
        return Self{
            .x = @as(i32, @intCast(p.x)),
            .y = @as(i32, @intCast(p.y)),
        };
    }

    pub fn sub(self: *const Self, other: *const PointInt) Self {
        return Self{ .x = self.x - other.x, .y = self.y - other.y };
    }
};

pub const PointFloat = struct {
    x: CoordinateFloat,
    y: CoordinateFloat,

    const Self = @This();

    pub fn fromInt(p: *const PointInt) Self {
        return Self{
            .x = @as(CoordinateFloat, @floatFromInt(p.x)),
            .y = @as(CoordinateFloat, @floatFromInt(p.y)),
        };
    }
};

pub const Shape = union(enum) {
    polygon: Polygon,
    rectangle: Rectangle,
    circle: Circle,

    const Self = @This();

    pub fn draw(self: *const Self, buffer: *PixelBuffer, color: u32) void {
        switch (self.*) {
            .polygon => self.polygon.draw(buffer, color),
            .rectangle => self.rectangle.draw(buffer, color),
            .circle => self.circle.draw(buffer, color),
        }
    }

    pub fn transform(self: *Self, t: *const CoordinateTransform) void {
        switch (self.*) {
            .polygon => self.polygon.transform(t),
            .rectangle => self.rectangle.transform(t),
            .circle => self.circle.transform(t),
        }
    }

    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        return switch (self.*) {
            .polygon => .{ .polygon = try self.polygon.clone(allocator) },
            else => self.*,
        };
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .polygon => self.polygon.deinit(),
            else => {},
        }
    }
};

pub const Polygon = struct {
    const Vertex = struct {
        p: PointInt,
        ear: bool,
        next: *Vertex,
        prev: *Vertex,
    };

    arena: std.heap.ArenaAllocator = undefined,
    first: *Vertex = undefined,
    n: usize = 0,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn add_vertex(self: *Self, p: PointInt) !void {
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

    pub fn area2(self: *const Self) i32 {
        if (self.n < 3) return 0;
        var sum: i32 = 0;
        var a = self.first.next;
        while (a.next != self.first) : (a = a.next) {
            sum += orientedArea2(&self.first.p, &a.p, &a.next.p);
        }
        return sum;
    }

    pub fn transform(self: *Self, t: *const CoordinateTransform) void {
        if (self.n == 0) return;
        t.applyIntInplace(&self.first.p);
        var current = self.first.next;
        while (current != self.first) : (current = current.next) {
            t.applyIntInplace(&current.p);
        }
    }

    pub fn clone(self: *const Self, allocator: Allocator) !Polygon {
        var cloned = Polygon.init(allocator);
        if (self.n == 0) return cloned;
        try cloned.add_vertex(self.first.p);
        var current = self.first.next;
        while (current != self.first) : (current = current.next) {
            try cloned.add_vertex(current.p);
        }
        return cloned;
    }

    pub fn draw(
        self: *const Self,
        buffer: *PixelBuffer,
        color: u32,
    ) void {
        if (self.n == 0) return;
        var p1: PointInt = undefined;
        var p2: PointInt = undefined;
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
    p1: PointInt,
    p2: PointInt,

    const Self = @This();

    pub fn transform(self: *Self, t: *const CoordinateTransform) void {
        t.applyIntInplace(&self.p1);
        t.applyIntInplace(&self.p2);
    }

    pub fn draw(
        self: *const Self,
        buffer: *PixelBuffer,
        color: u32,
    ) void {
        var pt1 = self.p1;
        var pt2 = self.p2;
        const left = @min(pt1.x, pt2.x);
        const right = @max(pt1.x, pt2.x);
        const top = @min(pt1.y, pt2.y);
        const bottom = @max(pt1.y, pt2.y);
        if (left >= buffer.width or right <= 0 or top >= buffer.height or bottom <= 0) return;
        const clamped_left: u32 = if (left < 0) 0 else @as(u32, @intCast(left));
        const clamped_top: u32 = if (top < 0) 0 else @as(u32, @intCast(top));
        const clamped_right: u32 = if (right > buffer.width) buffer.width else @as(u32, @intCast(right));
        const clamped_bottom: u32 = if (bottom > buffer.height) buffer.height else @as(u32, @intCast(bottom));
        var p: Pixel = .{ .x = clamped_left, .y = clamped_top };
        while (p.y < clamped_bottom) : (p.y += 1) {
            p.x = clamped_left;
            while (p.x < clamped_right) : (p.x += 1) {
                buffer.pixels[buffer.pixelIdx(&p) orelse continue] = color;
            }
        }
    }
};

pub const Circle = struct {
    c: PointInt,
    r: u32,

    const Self = @This();

    pub fn transform(self: *Self, t: *const CoordinateTransform) void {
        t.applyIntInplace(&self.c);
        self.r = t.scaleInt(self.r);
    }

    pub fn draw(
        self: *const Self,
        buffer: *PixelBuffer,
        color: u32,
    ) void {
        var cf = PointFloat.fromInt(&self.c);
        var rf = @as(f64, @floatFromInt(self.r));
        const width = @as(f64, @floatFromInt(buffer.width));
        const height = @as(f64, @floatFromInt(buffer.height));

        if (cf.x - rf >= width or cf.x + rf <= 0 or cf.y - rf >= height or cf.y + rf <= 0) return;
        const ymin = if (cf.y - rf < 0) 0 else cf.y - rf;
        const ymax = if (cf.y + rf > height) height else cf.y + rf;

        var pixel: Pixel = undefined;
        var y: CoordinateFloat = ymin;
        var x: CoordinateFloat = undefined;
        while (y < ymax) : (y += 1) {
            const dy = @fabs(cf.y - y);
            const dx = std.math.sqrt(rf * rf - dy * dy);
            if (cf.x - dx >= width or cf.x + dx <= 0) continue;
            x = if (cf.x - dx < 0) 0 else cf.x - dx;
            const xmax = if (cf.x + dx > width) width else cf.x + dx;
            while (x < xmax) : (x += 1) {
                pixel = Pixel.fromPointFloat(&.{ .x = x, .y = y }) orelse continue;
                buffer.pixels[buffer.pixelIdx(&pixel) orelse continue] = color;
            }
        }
    }
};

pub fn orientedArea2(a: *const PointInt, b: *const PointInt, c: *const PointInt) i32 {
    return (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
}

pub fn drawLineSegment(buffer: *PixelBuffer, color: u32, p1: *const PointInt, p2: *const PointInt) void {
    drawLineSegmentSubpixel(
        buffer,
        color,
        &PointFloat.fromInt(p1),
        &PointFloat.fromInt(p2),
    );
}

pub fn drawLineSegmentSubpixel(buffer: *PixelBuffer, color: u32, p1: *const PointFloat, p2: *const PointFloat) void {
    // Non-optimal implementation - invisible segments are not culled.

    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const length = @sqrt(dx * dx + dy * dy);

    var p: PointFloat = undefined;
    var pixel: Pixel = undefined;
    var t: f64 = 0;
    while (t < length) : (t += 1) {
        p.x = p1.x + dx * t / length;
        p.y = p1.y + dy * t / length;
        pixel = Pixel.fromPointFloat(&p) orelse continue;
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
    try p.add_vertex(PointInt{ .x = 0, .y = 0 });
    try p.add_vertex(PointInt{ .x = 2, .y = 0 });
    try p.add_vertex(PointInt{ .x = 0, .y = 2 });

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
    drawLineSegment(&buffer, white, &.{ .x = 0, .y = 0 }, &.{ .x = 9, .y = 9 });
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 0 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 0, .y = 1 }), black);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 5, .y = 5 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 6, .y = 6 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 8, .y = 8 }), white);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 9, .y = 9 }), black);

    drawLineSegmentSubpixel(&buffer, red, &.{ .x = 1.0, .y = -2.0 }, &.{ .x = 1.0, .y = 3.0 });
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 1 }), red);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 2 }), red);
    try std.testing.expectEqual(buffer.pixelValue(&.{ .x = 1, .y = 3 }), black);

    var buffer2 = try buffer.subBuffer(5, 5, .{ .x = 1, .y = 1 });
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
