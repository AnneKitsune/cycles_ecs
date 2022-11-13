const std = @import("std");
const Entity = @import("entity.zig").Entity;

pub fn Archetype(comptime tuple: anytype) type {
    return struct {
        data: std.MultiArrayList(tuple),
        // O(1) access to the array id from the entity id for swapRemove
        entity_to_idx: std.AutoArrayHashMap(Entity, usize),
        // used on removal to update entity_to_idx
        idx_to_entity: std.ArrayList(Entity),
        alloc: std.mem.Allocator,

        const types = tuple;
        const S = @This();

        pub fn init(allocator: std.mem.Allocator) !S {
            const ty = std.MultiArrayList(types);
            var multi: ty = ty{};
            try multi.ensureTotalCapacity(allocator, 8);

            const entity_map = std.AutoArrayHashMap(Entity, usize).init(allocator);
            const idx_link = std.ArrayList(Entity).init(allocator);
            return S{
                .data = multi,
                .alloc = allocator,
                .entity_to_idx = entity_map,
                .idx_to_entity = idx_link,
            };
        }
        pub fn deinit(self: *S) void {
            self.data.deinit(self.alloc);
            self.entity_to_idx.deinit();
            self.idx_to_entity.deinit();
        }
        pub fn insert(self: *S, data: types) !Entity {
            const entity = Entity.new();
            try self.entity_to_idx.put(entity, self.data.len);
            try self.idx_to_entity.append(entity);
            try self.data.append(self.alloc, data);

            return entity;
        }
        pub fn remove(self: *S, entity: Entity) !void {
            if (self.entity_to_idx.fetchSwapRemove(entity)) |kv| {
                // The last element will go in idx.
                // Thus, idx_to_entity and entity_to_idx both need to be updated to point to this new slot
                const idx = kv.value;
                // the last entity gets moved to the empty slot
                const last_entity = self.idx_to_entity.pop();

                self.data.swapRemove(idx);

                // fixup the tracking hashmap and list
                if (entity.id != last_entity.id) {
                    try self.entity_to_idx.put(last_entity, idx);
                    self.idx_to_entity.items[idx] = last_entity;
                }
            } else {
                @panic("Tried to remove an entity from an archetype storage but the entity is not inside of the storage. This should never happen.");
            }
        }
    };
}

test "add/remove archetype" {
    var storage = try Archetype(std.meta.Tuple(&.{u32})).init(std.testing.allocator);
    defer storage.deinit();

    const ent0 = try storage.insert(.{0});
    try storage.remove(ent0);

    const ent1 = try storage.insert(.{1});
    const ent2 = try storage.insert(.{2});
    const ent3 = try storage.insert(.{3});

    try storage.remove(ent2);
    try storage.remove(ent1);
    try storage.remove(ent3);

    const ent4 = try storage.insert(.{4});
    const ent5 = try storage.insert(.{5});
    try storage.remove(ent4);
    const ent6 = try storage.insert(.{6});
    try storage.remove(ent6);
    try storage.remove(ent5);
}
