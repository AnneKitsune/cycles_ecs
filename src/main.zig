const std = @import("std");
const testing = std.testing;

pub const Entity = @import("entity.zig").Entity;
pub const Archetypes = @import("archetypes.zig").Archetypes;

// entity { alive list (id, gen), dead list }
// system { args }
// world { resources (including entity list, entity map, storages)  }
// storage<T> { data: AutoArrayList(T) }
// entity_map<C> { hashmap entity -> index into component storage } // how to point to the correct storage?
// dispatcher { systems }
//
// insert_component(entity, component: anytype)
// get_component
// get_component_mut
// delete_component<C>(entity)
//
// join<CS (iter return type, with pointers)> (world) -> iterator
// run_system(world, system_fn)
//
// should systems be able to return errors? can they be handled at all from outside of the systems?

