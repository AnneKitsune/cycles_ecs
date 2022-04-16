const std = @import("std");
const Entity = @import("entity.zig").Entity;
var next_archetype_id: usize = 0;

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
            return S {
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
            //var s = @ptrCast(*S, @alignCast(@typeInfo(*S).Pointer.alignment, self));
            self.data.swapRemove(idx);
        }
    };
}

// number -> function ptr where function knows it's parent.

const remove_fn_proto = fn (usize) void;

pub fn Archetypes(comptime type_slice: []const []const type) type {
    // Convert []const []const type to Tuple(Archetype(Tuple([]const type)))
    comptime var generated_tuples: [type_slice.len]type = undefined;
    comptime var generated_storages: [type_slice.len]type = undefined;
    inline for (type_slice) |inner_types, i| {
        generated_tuples[i] = std.meta.Tuple(inner_types);
        generated_storages[i] = Archetype(generated_tuples[i]);
    }

    const archetypes_types = std.meta.Tuple(&generated_storages);

    return struct {
        archetypes: archetypes_types,
        entity_map: std.AutoArrayHashMap(Entity, u16),
        //remove_fns: [type_slice.len]remove_fn_proto,

        const S = @This();
        pub fn init(allocator: std.mem.Allocator) !S {
            var gen: archetypes_types = undefined;
            inline for (std.meta.fields(archetypes_types)) |field| {
                @field(gen, field.name) = try field.field_type.init(allocator);
            }
            var s = S {
                .archetypes = gen,
                .entity_map = std.AutoArrayHashMap(Entity, u16).init(allocator),
                //.remove_fns = undefined,
            };
            //s.register_rm_funcs();
            return s;
        }
//        fn register_rm_funcs(self: *S) void {
//            inline for (std.meta.fields(archetypes_types)) |field, i| {
//                    fn rm_fn_inner(idx: usize) void {
//                        @field(self.archetypes, field.name).remove(idx);
//                    }
//                //const remove_fn: remove_fn_proto = @field(gen, field.name).remove;
//                self.remove_fns[i] = gen_str.rm_fn_inner;
//            }
//        }
        pub fn deinit(self: *S) void {
            inline for (std.meta.fields(archetypes_types)) |field| {
                @field(self.archetypes, field.name).deinit();
            }
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
                    try archetype.insert(converted);
                    const entity = Entity.new();
                    try self.entity_map.put(entity, arch_id);
                    // Runtime end.

                    return entity;
                }
            }
            @compileError("Failed to find archetype for type: "++@typeName(@TypeOf(data)));
        }
        pub fn remove(self: *S, entity: Entity) void {
            if (self.entity_map.fetchSwapRemove(entity)) |kv| {
                const arch_id = kv.value;
                const id = @as(usize, entity.id);
                inline for (std.meta.fields(archetypes_types)) |field, i| {
                    // runtime
                    // TODO optimize using an array of functions ptr
                    if (i == arch_id) {
                        @field(self.archetypes, field.name).remove(id);
                        return;
                    }
                }
                //self.remove_fns[arch_id](@intCast(usize, entity.id));
            }
        }
        fn user_types_len(comptime types: anytype) usize {
            return std.meta.fields(@TypeOf(types)).len;
        }
        fn convert_user_types(comptime types: anytype) [2][user_types_len(types)]type {

            const user_tuple = types;
            const user_tuple_fields = std.meta.fields(@TypeOf(user_tuple));

            // tuple of pointer of types to slice of types
            comptime var user_types: [user_tuple_fields.len]type = undefined;
            comptime var converted_slice_types: [user_tuple_fields.len]type = undefined;
            inline for (user_tuple_fields) |field, i| {
                const field_type = @field(user_tuple, field.name);
                const field_info = @typeInfo(field_type);
                // We have a tuple of types, where the types are pointers to type
                if (field_info != .Pointer) {
                    @compileError("Iter arguments must be tuple of pointers. Got "++@typeName(field_type));
                }
                user_types[i] = field_info.Pointer.child;
                if (field_info.Pointer.is_const) {
                    converted_slice_types[i] = []const field_info.Pointer.child;
                } else {
                    converted_slice_types[i] = []field_info.Pointer.child;
                }
            }
            return .{user_types, converted_slice_types};
        }
        fn count_compatible_slices(comptime user_types: anytype) usize {
            comptime var slice_count = 0;
            // for self.archetypes find matching
            // increment slice_count each time you match
            inline for (generated_tuples) |archetype_tuple| {
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
                    slice_count += 1;
                }
            }
            return slice_count;
        }
        fn output_tuple_ty(comptime types: anytype) type {
            const both = convert_user_types(types);
            const tuple_ty = std.meta.Tuple(&both[1]);
            return tuple_ty;
        }
        fn output_iter_ty(comptime types: anytype) type {
            const both = convert_user_types(types);
            const count = count_compatible_slices(both[0]);
            const tuple_ty = output_tuple_ty(types);
            return [count]tuple_ty;
        }
        pub fn iter(self: *S, comptime types: anytype) output_iter_ty(types) {
            // Find all archetypes containing all types pointed to by the pointers.

            // Example iterating .{*constA, *B} over {A,B,C}, {A,B}
            //const user_tuple = types;
            //const user_tuple_fields = std.meta.fields(@TypeOf(user_tuple));

            const both = comptime convert_user_types(types);
            const user_types = both[0];
            //const converted_slice_types = both[1];

            // convert user type .{*const A, *B} into .{[]const A, []B}
            const converted_user_tuple_type = output_tuple_ty(types);

            //const slice_count: usize = comptime count_compatible_slices(user_types);

            const converted_output_type = output_iter_ty(types);
            var all: converted_output_type = undefined;
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

//            for (all) |slice| {
//                var i: usize = 0;
//                while (i < slice.len) : (i += 1) {
//                    // do stuff with slice.@"0"[i]
//                }
//            }

            return all;
        }
    };
}

pub fn Query(comptime types: type) type {
    _ = types;
    return struct {
    };
}

test "archetypes" {
    // create archetype storage
    var archetypes = try Archetypes(&[_][]const type{
        &[_]type{u32, u64},
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
    archetypes.remove(ent1);
    try std.testing.expect(archetypes.archetypes.@"1".data.slice().len == 0);

    // iter
    const slices = archetypes.iter(.{*u32, *const u64});
    for (slices) |slice| {
        var i: usize = 0;
        while (i < slice[0].len) : (i += 1) {
            slice[0][i] += @intCast(u32, slice[1][i]);
        }
    }
}
