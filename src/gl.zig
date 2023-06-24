const std = @import("std");

pub const screen = @import("screen.zig");
pub const geometry = @import("geometry.zig");
pub const primitives = @import("primitives.zig");

pub const PixelBuffer = screen.PixelBuffer;

test {
    std.testing.refAllDecls(@This());
}
