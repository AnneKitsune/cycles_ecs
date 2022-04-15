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
        pub fn remove(self: *anyopaque, idx: usize) void {
            var s = @ptrCast(*S, @alignCast(@typeInfo(*S).Pointer.alignment, self));
            s.data.swapRemove(idx);
        }
    };
}

const remove_fn_proto = fn (usize) void;

pub fn Archetypes(comptime type_slice: []const []const type) type {
    // Convert []const []const type to []const Archetype(Tuple([]const type))
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
            comptime var found = false;
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

                    found = true;
                    return entity;
                }
            }
            if (!found) {
                @compileError("Failed to find archetype for type: "++@typeName(@TypeOf(data)));
            }
        }
//        pub fn remove(self: *S, entity: Entity) void {
//            if (self.entity_map.fetchSwapRemove(entity)) |kv| {
//                const arch_id = kv.value;
//                self.remove_fns[arch_id](@intCast(usize, entity.id));
//            }
//        }
    };
}

test "multiarray" {
    const A = struct {a: u32};
    const ty = std.MultiArrayList(A);
    var multi: ty = ty{};
    defer multi.deinit(std.testing.allocator);
    try multi.append(std.testing.allocator, A {.a = 55});
    try std.testing.expect(multi.slice().len == 1);
}

test "archetypes" {
    var archetypes = try Archetypes(&[_][]const type{
        &[_]type{u32, u64},
        &[_]type{u32},
    }).init(std.testing.allocator);
    defer archetypes.deinit();
    const v: u32 = 55;
    _ = try archetypes.insert(.{v});
    try std.testing.expect(archetypes.archetypes.@"0".data.slice().len == 0);
    try std.testing.expect(archetypes.archetypes.@"1".data.slice().len == 1);
    //archetypes.remove(ent1);
}
