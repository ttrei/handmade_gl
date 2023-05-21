const std = @import("std");

const FileSource = std.build.FileSource;

pub fn build(b: *std.Build) void {
    b.addModule("handmade_gl", .{
        .source_file = FileSource.relative("src/gl.zig"),
    });
}
