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
/// Pixel buffer representing the camera view.
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
        .buffer = screen_buffer.subBuffer(position, width, height),
        .screen_buffer = screen_buffer,
    };
}

pub fn updateBuffer(self: *Self) void {
    self.buffer = self.screen_buffer.subBuffer(self.position, self.width, self.height);
}

pub fn screenToWorldCoordinates(self: *const Self, screen_coords: Pixel) Point {
    return self.transform.reverse(.{
        .x = @floatFromInt(screen_coords.x - self.position.x),
        .y = @floatFromInt(screen_coords.y - self.position.y),
    });
}

pub fn drawOutline(self: *Self, color: u32) void {
    const rect = geometry.Rectangle{
        .p1 = .{ .x = 0, .y = 0 },
        .p2 = .{ .x = @floatFromInt(self.width), .y = @floatFromInt(self.height) },
    };
    rect.drawOutline(&self.buffer, color);
}