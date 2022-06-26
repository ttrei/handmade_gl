const std = @import("std");

const Allocator = std.mem.Allocator;

// Platform-independent ScreenBuffer of pixels + code for rendering geometry primitives.
// Application code renders to the ScreenBuffer which is then displayed by platform code.

pub const ScreenCoordinates = struct {
    x: i32,
    y: i32,
};

pub const SubPixelScreenCoordinates = struct {
    x: f64,
    y: f64,
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
        self.drawFilledRectangle(
            color,
            0,
            0,
            @intCast(i32, self.width),
            @intCast(i32, self.height),
        );
    }

    pub fn drawLineSegment(self: *ScreenBuffer, color: u32, x1: f64, y1: f64, x2: f64, y2: f64) void {
        // Non-optimal implementation - invisible segments are not culled.

        const dx = x2 - x1;
        const dy = y2 - y1;
        const length = @sqrt(dx * dx + dy * dy);

        var x: i32 = undefined;
        var y: i32 = undefined;
        var t: f64 = 0;
        while (t < length) : (t += 1) {
            x = @floatToInt(i32, x1 + dx * t / length);
            y = @floatToInt(i32, y1 + dy * t / length);
            if (x < 0 or x >= self.width or y < 0 or y >= self.height) continue;
            self.pixels[@intCast(u32, y) * self.width + @intCast(u32, x)] = color;
        }
    }

    pub fn drawFilledRectangle(self: *ScreenBuffer, color: u32, left: i32, top: i32, right: i32, bottom: i32) void {
        if (left >= self.width or right <= 0 or top >= self.height or bottom <= 0) return;
        const clamped_left: u32 = if (left < 0) 0 else @intCast(u32, left);
        const clamped_top: u32 = if (top < 0) 0 else @intCast(u32, top);
        const clamped_right: u32 = if (right > self.width) self.width else @intCast(u32, right);
        const clamped_bottom: u32 = if (bottom > self.height) self.height else @intCast(u32, bottom);
        var row_start: u32 = self.width * clamped_top + clamped_left;
        var y: u32 = 0;
        const height = clamped_bottom - clamped_top;
        while (y < height) : (y += 1) {
            const width = clamped_right - clamped_left;
            var x: u32 = 0;
            while (x < width) : (x += 1) self.pixels[row_start + x] = color;
            row_start += self.width;
        }
    }

    pub fn drawFilledCircle(self: *ScreenBuffer, color: u32, x0: i64, y0: i64, r: u32) void {
        if (x0 - r >= self.width or x0 + r <= 0 or y0 - r >= self.height or y0 + r <= 0) return;
        const ymin = if (y0 - r < 0) 0 else @intCast(u32, y0 - r);
        const ymax = if (y0 + r > self.height) self.height else @intCast(u32, y0 + r);

        var y: u32 = ymin;
        while (y < ymax) : (y += 1) {
            const dy = std.math.absCast(y0 - y);
            const dx = std.math.sqrt(r * r - dy * dy);
            if (x0 - dx >= self.width or x0 + dx <= 0) continue;
            const xmin = if (x0 - dx < 0) 0 else @intCast(u32, x0 - dx);
            const xmax = if (x0 + dx > self.width) self.width else @intCast(u32, x0 + dx);
            const row_start = self.width * y;
            var x: u32 = xmin;
            while (x < xmax) : (x += 1) self.pixels[row_start + x] = color;
        }
    }
};
