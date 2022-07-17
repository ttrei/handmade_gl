const std = @import("std");
const screen = @import("screen.zig");
const ScreenBuffer = screen.ScreenBuffer;

const Allocator = std.mem.Allocator;

const CoordinateType = i32;

pub const Point = struct {
    x: CoordinateType,
    y: CoordinateType,
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

    const Self = @This();

    pub fn init() Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
    }
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn add_vertex(self: *Self, p: Point) !void {
        // TODO: Is it OK to call arena.allocator() each time?
        const v = try self.arena.allocator().create(Vertex);
        if (self.n == 0) {
            v.* = .{
                .p = p,
                .ear = false,
                .next = v,
                .prev = v,
            };
            self.first = v;
        } else {
            v.* = .{
                .p = p,
                .ear = false,
                .next = self.first,
                .prev = self.first.prev,
            };
            self.first.prev = v;
            v.prev.next = v;
        }
        self.n += 1;
    }

    pub fn area2(self: *const Self) i32 {
        if (self.n < 3) return 0;
        var sum: i32 = 0;
        const f = self.first;
        var a = f.next;
        while (a.next != f) : (a = a.next) {
            sum += orientedArea2(&f.p, &a.p, &a.next.p);
        }
        return sum;
    }

    pub fn draw(self: *const Self, buffer: *ScreenBuffer, color: u32) void {
        var i: usize = 0;
        var v = self.first;
        while (i < self.n) : (i += 1) {
            screen.lineSegment(
                buffer,
                color,
                &screen.Point{ .x = v.p.x, .y = v.p.y },
                &screen.Point{ .x = v.next.p.x, .y = v.next.p.y },
            );
            v = v.next;
        }
    }
};

pub fn orientedArea2(a: *const Point, b: *const Point, c: *const Point) i32 {
    return (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y);
}
