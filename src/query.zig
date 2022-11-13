const comptime_utils = @import("comptime_utils.zig");
pub fn Query(comptime requested_types: anytype, comptime archetype_types: []const []const type) type {
    return struct {
        slices: comptime_utils.output_iter_ty(archetype_types, requested_types),
        const S = @This();
        pub const TYPES = requested_types;
        pub fn init(archetypes: anytype) S {
            return S {
                .slices = archetypes.iter(requested_types),
            };
        }
    };
}
