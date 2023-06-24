const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ScreenCoordinate = i32;
pub const ScreenCoordinateSubPixel = f64;

// TODO
//
// THINK DEEPLY ABOUT COORDINATE SYSTEMS!!

pub const Pixel = struct {
    x: ScreenCoordinate,
    y: ScreenCoordinate,

    pub fn fromSubPixel(p: *const SubPixel) Pixel {
        return Pixel{
            .x = @intFromFloat(ScreenCoordinate, p.x),
            .y = @intFromFloat(ScreenCoordinate, p.y),
        };
    }

    pub fn sub(p: *const Pixel, other: Pixel) Pixel {
        return Pixel{
            .x = p.x - other.x,
            .y = p.y - other.y,
        };
    }
};

pub const SubPixel = struct {
    x: ScreenCoordinateSubPixel,
    y: ScreenCoordinateSubPixel,

    pub fn fromPixel(p: *const Pixel) SubPixel {
        return SubPixel{
            .x = @floatFromInt(ScreenCoordinateSubPixel, p.x),
            .y = @floatFromInt(ScreenCoordinateSubPixel, p.y),
        };
    }
};

// Rectangular subset of a row-major pixel array
pub const PixelBuffer = struct {
    pixels: []u32,
    // Dimensions of the subset
    width: u32,
    height: u32,
    // How many pixels have to be skipped to go directly one row down
    stride: u32,
    // coordinates of the top-left pixel of the subset
    origin: Pixel,
    const Self = @This();

    // Initialize to the subset containing the whole array
    pub fn init(pixels: []u32, width: u32, height: u32) !Self {
        if (pixels.len != width * height) {
            return error.InvalidPixelBuffer;
        }
        return Self{
            .pixels = pixels,
            .width = width,
            .height = height,
            .stride = width,
            .origin = .{ .x = 0, .y = 0 },
        };
    }

    pub fn subBuffer(self: *const Self, width: u32, height: u32, origin: Pixel) Self {
        return Self{
            .pixels = self.pixels,
            .width = width,
            .height = height,
            .stride = self.stride,
            .origin = origin,
        };
    }

    pub fn clear(self: *Self, color: u32) void {
        const x_max = @min(self.origin.x + @intCast(i32, self.width), @intCast(i32, self.stride));
        const y_max = @min(self.origin.y + @intCast(i32, self.height), @intCast(i32, self.pixels.len / self.stride));
        var y = @max(self.origin.y, 0);
        while (y < y_max) : (y += 1) {
            var x = @max(self.origin.x, 0);
            while (x < x_max) : (x += 1) {
                self.pixels[y * self.stride + x] = color;
            }
        }
    }

    // Calculate index of a Pixel, given coordinates relative to the subbuffer origin
    pub fn pixelIdx(self: *const Self, p: Pixel) ?u32 {
        // Outside of the subbuffer
        if (p.x < 0 or p.y < 0 or p.x > self.width or p.y > self.height) return null;
        const x = p.x + self.origin.x;
        const y = p.y + self.origin.y;
        const x_max = self.stride;
        const y_max = self.pixels.len / self.stride;
        // Outside of the total buffer
        if (x < 0 or y < 0 or x >= x_max or y >= y_max) return null;
        return @intCast(u32, y) * self.stride + @intCast(u32, x);
    }
};

test "pixel buffer" {
    const width = 800;
    const height = 600;
    const stride = width;
    const pixels = try std.testing.allocator.alloc(u32, width * height);
    defer std.testing.allocator.free(pixels);
    const buffer = try PixelBuffer.init(pixels, width, height);
    try std.testing.expect(buffer.pixels.len == width * height);

    const buffer2 = buffer.subBuffer(50, 10, .{ .x = 10, .y = 20 });
    try std.testing.expect(buffer2.origin.x == 10);
    try std.testing.expect(buffer2.pixelIdx(.{ .x = 0, .y = 0 }) == 20 * stride + 10);
}
