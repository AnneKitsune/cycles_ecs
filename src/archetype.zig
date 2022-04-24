const std = @import("std");

pub fn Archetype(comptime tuple: anytype) type {
    return struct {
        data: std.MultiArrayList(tuple),
        alloc: std.mem.Allocator,

        const types = tuple;
        const S = @This();

        pub fn init(allocator: std.mem.Allocator) !S {
            const ty = std.MultiArrayList(types);
            var multi: ty = ty{};
            try multi.ensureTotalCapacity(allocator, 8);
            return S{
                .data = multi,
                .alloc = allocator,
            };
        }
        pub fn deinit(self: *S) void {
            self.data.deinit(self.alloc);
        }
        pub fn insert(self: *S, data: types) !void {
            try self.data.append(self.alloc, data);
        }
        pub fn remove(self: *S, idx: usize) void {
            self.data.swapRemove(idx);
        }
    };
}
