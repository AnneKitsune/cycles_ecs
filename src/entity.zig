const std = @import("std");

var next_id = std.atomic.Atomic(u64).init(0);

pub const Entity = struct {
    id: u64,
    const S = @This();
    pub fn new() S {
        return S{
            .id = next_id.fetchAdd(1, .Monotonic),
        };
    }
};

test "Create two entities" {
    const first = Entity.new();
    const second = Entity.new();
    // Only true if test run serially.
    try std.testing.expect(first.id == second.id - 1);
}
