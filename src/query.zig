const comptime_utils = @import("comptime_utils.zig");
pub fn Query(types: anytype) type {
    return struct {
        slices: comptime_utils.output_iter_ty(types),
    };
}
