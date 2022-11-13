const std = @import("std");
const Entity = @import("entity.zig").Entity;
const comptime_utils = @import("comptime_utils.zig");
const Archetype = @import("archetype.zig").Archetype;

pub fn Archetypes(comptime type_slice: []const []const type) type {
    // Convert []const []const type to Tuple(Archetype(Tuple([]const type)))
    const generated_tuples = comptime_utils.typeSliceToTuples(type_slice);
    const generated_storages = comptime_utils.tupleSliceToArchetypeSlice(&generated_tuples);

    const archetypes_types = std.meta.Tuple(&generated_storages);

    return struct {
        archetypes: archetypes_types,
        entity_map: std.AutoArrayHashMap(Entity, u16),

        const S = @This();
        pub fn init(allocator: std.mem.Allocator) !S {
            var s = S{
                .archetypes = try comptime_utils.generateArchetypesStorage(archetypes_types, allocator),
                .entity_map = std.AutoArrayHashMap(Entity, u16).init(allocator),
            };
            return s;
        }

        pub fn deinit(self: *S) void {
            comptime_utils.deinitArchetypesStorage(&self.archetypes);
            self.entity_map.deinit();
        }

        pub fn insert(self: *S, data: anytype) !Entity {
            const data_fields = std.meta.fields(@TypeOf(data));
            inline for (generated_tuples) |types_of_archetype, arch_id| {
                const tuple_fields = std.meta.fields(types_of_archetype);
                if (tuple_fields.len != data_fields.len) {
                    continue;
                }
                // Check if all fields are equal in types
                comptime var mismatch = false;
                inline for (tuple_fields) |archetype_field, i| {
                    const left = data_fields[i].field_type;
                    const right = archetype_field.field_type;
                    if (left != right) {
                        mismatch = true;
                        break;
                    }
                }
                if (!mismatch) {
                    // Runtime start.
                    var archetype = &@field(self.archetypes, std.meta.fields(archetypes_types)[arch_id].name);
                    var converted: generated_tuples[arch_id] = undefined;
                    comptime {
                        inline for (tuple_fields) |f, i| {
                            @field(converted, f.name) = @field(data, data_fields[i].name);
                        }
                    }
                    const entity = try archetype.insert(converted);
                    try self.entity_map.put(entity, arch_id);
                    // Runtime end.
                    return entity;
                }
            }
            @compileError("Failed to find archetype for type: " ++ @typeName(@TypeOf(data)));
        }
        pub fn remove(self: *S, entity: Entity) !void {
            if (self.entity_map.fetchSwapRemove(entity)) |kv| {
                const arch_id = kv.value;
                inline for (std.meta.fields(archetypes_types)) |field, i| {
                    // TODO optimize using an array of functions ptr
                    if (i == arch_id) {
                        // there's no Entity -> archetype storage id map because the swap remove operations will invalidate the storage id
                        try @field(self.archetypes, field.name).remove(entity);
                        return;
                    }
                }
            }
        }

        /// Returns a slice over slices of the requested query type.
        /// A query of .{*const A, *B} over {A,B},{A} archetypes will return
        /// []{.{[]const A, []B}}
        pub fn iter(self: *S, comptime types: anytype) comptime_utils.output_iter_ty(type_slice, types) {
            // Find all archetypes containing all types pointed to by the pointers.

            const user_types = comptime_utils.pointersTupleToTypes(types);

            const converted_output_type = comptime_utils.output_iter_ty(type_slice, types);
            var all: converted_output_type = undefined;
            const converted_user_tuple_type = @TypeOf(all[0]);
            comptime var insert_idx = 0;

            // for self.archetypes find matching
            inline for (generated_tuples) |archetype_tuple, archetype_idx| {
                comptime var not_found = false;

                // For all types requested by the user
                inline for (user_types) |user_type| {
                    // Search if the archetype contains it.
                    comptime var found_type = false;
                    inline for (std.meta.fields(archetype_tuple)) |archetype_field| {
                        if (archetype_field.field_type == user_type) {
                            found_type = true;
                            break;
                        }
                    }
                    if (!found_type) {
                        not_found = true;
                    }
                }
                // The archetype contains all the requested user types.
                if (!not_found) {
                    var write_tuple: converted_user_tuple_type = undefined;
                    const archetype_storage = &self.archetypes[archetype_idx];
                    const archetype_data = &archetype_storage.data;
                    const archetype_slice = archetype_data.slice();

                    inline for (user_types) |user_type, tuple_idx| {
                        inline for (std.meta.fields(archetype_tuple)) |archetype_field, archetype_enum| {
                            if (archetype_field.field_type == user_type) {
                                const archetype_tuple_field_enum = std.meta.FieldEnum(archetype_tuple);
                                const atf = @intToEnum(archetype_tuple_field_enum, archetype_enum);

                                const items = archetype_slice.items(atf);
                                write_tuple[tuple_idx] = items;
                                break;
                            }
                        }
                    }
                    all[insert_idx] = write_tuple;
                    insert_idx += 1;
                }
            }

            return all;
        }
    };
}

test "archetypes" {
    // create archetype storage
    var archetypes = try Archetypes(&[_][]const type{
        &[_]type{ u32, u64 },
        &[_]type{u32},
        &[_]type{u64},
    }).init(std.testing.allocator);
    defer archetypes.deinit();

    // insert archetype
    const v: u32 = 55;
    const ent1 = try archetypes.insert(.{v});
    try std.testing.expect(archetypes.archetypes.@"0".data.slice().len == 0);
    try std.testing.expect(archetypes.archetypes.@"1".data.slice().len == 1);

    // remove archetype
    try archetypes.remove(ent1);
    try std.testing.expect(archetypes.archetypes.@"1".data.slice().len == 0);

    // iter
    const slices = archetypes.iter(.{ *u32, *const u64 });
    for (slices) |slice| {
        var i: usize = 0;
        while (i < slice[0].len) : (i += 1) {
            slice[0][i] += @intCast(u32, slice[1][i]);
        }
    }
}
