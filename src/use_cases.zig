const Comp1 = struct {};
const Comp2 = struct {
    a: u32,
};
const Res1 = struct {};

const entity = Entity.new();

test "create/delete entity world" {
    // The components must match those declared on the world struct, both in composition and order.
    const entity = world.ecs.insert(.{Comp1{}, Comp2{.a = 55,}});
    // Uses an hashmap (or vec) Entity -> Archetype to know where to delete.
    world.ecs.kill(entity);
    // To create/delete an entity from a system, use a closure taking world.ecs and executing insert/kill. Execute them all at the end of a frame.
}
test "get component" {
    // Use a query. The query locks all the possible archetypes. It contains a const ptr to the Entity -> Archetype+Position hashmap ptr.
    // Iterating using it is slow but yields the entities of the archetype.
    const query = Query(.{*Comp1}).new(&world.ecs);
    var comp1: ?*Comp1 = query.get(target_entity);
}
test "iter from world" {
    const query = Query(.{*const Comp1, *Comp2}).new(&world.ecs);
    var iter = query.iter();
    while (iter.next()) |tuple| {
    }
    // Iter through the hashmap and collect those that match the target archetypes id. Return (entity, .{components})
    var iter2 = query.iter_with_entities();
    while (iter2.next()) |tuple| {
    }
    // Iter through the hashmap and collect those that match the target archetypes id.
    var iter3 = query.entities();
    while (iter3.next()) |entity| {
    }
}

fn sys(query: Query(.{*const Comp1, *Comp2})) void {
    var iter = query.iter();
    while (iter.next()) |tuple| {
    }
}
test "iter from system" {
    const sys_fn = sys;
}

fn sys2(res: *Res1) void {
}
test "resource from system" {
    const sys_fn = sys2;
}
test "resource from world" {
    // world is a user-created struct. one of the fields is used to store entities and archetypes.
    const EntityComponents = ecs.Archetypes(.{
        .{Transform},
        .{Transform, Player},
        .{Transform, Mob, Following, Ai},
        .{Transform, Mob, Following, Ai2},
    });
    const World = struct {
        my_res: u32,
        ecs: EntityComponents,
    };
    var world = World {
        .my_res = 55,
        .ecs = EntityComponents.init(alloc),
    };
    world.my_res = 56;
}
test "dispatcher" {
    const dispatcher = Dispatcher(.{
        sys,
        sys2,
    });
    // Multithreading, if enabled.
    dispatcher.run();
    // Always singlethreaded.
    dispatcher.run_sequential();
}
