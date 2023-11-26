const geometry = @import("geometry.zig");
const Transform = geometry.Transform;
const Point = geometry.Point;

const screen = @import("screen.zig");
const Pixel = screen.Pixel;
const PixelBuffer = screen.PixelBuffer;

const Self = @This();

/// Position of the camera (in pixels)
position: Pixel,
/// Size of the camera (in pixels)
width: u32,
height: u32,
/// Transforms from world coordinates to camera coordinates
transform: Transform,
/// Pixel sub-buffer representing the on-screen part of the camera view.
buffer: PixelBuffer,
/// The screen buffer backing the sub-buffer.
screen_buffer: *const PixelBuffer,

pub fn init(
    position: Pixel,
    width: u32,
    height: u32,
    transform: Transform,
    screen_buffer: *const PixelBuffer,
) !Self {
    return .{
        .position = position,
        .width = width,
        .height = height,
        .transform = transform,
        .buffer = Self.getSubBuffer(position, width, height, screen_buffer),
        .screen_buffer = screen_buffer,
    };
}

pub fn updateBuffer(self: *Self) void {
    self.buffer = Self.getSubBuffer(self.position, self.width, self.height, self.screen_buffer);
}

pub fn screenToWorldCoordinates(self: *const Self, screen_coords: Pixel) Point {
    return self.transform.reverse(.{
        .x = @floatFromInt(screen_coords.x - self.position.x),
        .y = @floatFromInt(screen_coords.y - self.position.y),
    });
}

fn getSubBuffer(position: Pixel, width: u32, height: u32, screen_buffer: *const PixelBuffer) PixelBuffer {
    const left = @max(position.x, 0);
    const top = @max(position.y, 0);
    const right = @min(position.x + @as(i32, @intCast(width)), @as(i32, @intCast(screen_buffer.width)));
    const bottom = @min(position.y + @as(i32, @intCast(height)), @as(i32, @intCast(screen_buffer.height)));
    if (left >= screen_buffer.width or top >= screen_buffer.height or right < 0 or bottom < 0) {
        return PixelBuffer.initEmpty();
    }
    return screen_buffer.subBuffer(
        @intCast(right - left),
        @intCast(bottom - top),
        .{ .x = left, .y = top },
    ) catch unreachable;
}
