const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ScreenCoordinate = i32;
pub const ScreenCoordinateSubPixel = f64;

pub const Pixel = struct {
    x: ScreenCoordinate,
    y: ScreenCoordinate,

    pub fn fromSubPixel(p: *const SubPixel) Pixel {
        return Pixel{
            .x = @floatToInt(ScreenCoordinate, p.x),
            .y = @floatToInt(ScreenCoordinate, p.y),
        };
    }
};

pub const SubPixel = struct {
    x: ScreenCoordinateSubPixel,
    y: ScreenCoordinateSubPixel,

    pub fn fromPixel(p: *const Pixel) SubPixel {
        return SubPixel{
            .x = @intToFloat(ScreenCoordinateSubPixel, p.x),
            .y = @intToFloat(ScreenCoordinateSubPixel, p.y),
        };
    }
};

// Platform-independent ScreenBuffer of pixels.
// Application code renders to the ScreenBuffer which is then displayed by platform code.

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
        for (self.pixels) |*pixel| {
            pixel.* = color;
        }
    }
};
