const std = @import("std");
const Archetypes = @import("archetypes.zig").Archetypes;
const Query = @import("query.zig").Query;
const comptime_utils = @import("comptime_utils.zig");

pub fn Dispatcher(comptime world_ty: type, systems: anytype) type {
    return struct {
        const S = @This();
        pub fn run_seq(_: *S, world: *world_ty) void {
            inline for (std.meta.fields(@TypeOf(systems))) |system_tuple_field| {
                const system = @field(systems, system_tuple_field.name);
                callSystem(world, system);
            }
        }
        pub fn run_par(_: *S, world: *world_ty) void {
            @setEvalBranchQuota(100_000);

            const system_count = std.meta.fields(@TypeOf(systems)).len;
            comptime var system_running: [system_count]bool = undefined;
            inline for (system_running) |*b| {
                b.* = false;
            }

            const systems_fields = std.meta.fields(@TypeOf(systems));
            var system_frames: [system_count]anyframe->void = undefined;

            // Iter over systems
            inline for (systems_fields) |field, i| {
                const system = @field(systems, field.name);
                const system_borrows = systemArgs(system);
                comptime var j: usize = 0;
                inline while (j < system_borrows.count) : (j += 1) {
                    const borrow = system_borrows.types[j];
                    // Check that no currently running systems borrows it too in
                    // an incompatible way.
                    inline for (system_running) |running, check_i| {
                        if (!running) {
                            continue;
                        }
                        // Check borrows
                        const running_borrows = systemArgs(systems_fields[check_i].ty);

                        // Force the system to complete before we run our system?
                        comptime var force_complete = false;
                        for (running_borrows) |running_borrow| {
                            if (borrow.ty == running_borrow.ty) {
                                if (borrow.mut || running_borrow.mut) {
                                    force_complete = true;
                                    break;
                                }
                            }
                        }
                        if (force_complete) {
                            await system_frames[i];
                            system_running[check_i] = false;
                        }
                    }
                }
                system_frames[i] = &async callSystem(world, @field(systems, field.name));
            }

            // Await remaining systems
            inline for (system_running) |*running, i| {
                if (running.*) {
                    await system_frames[i];
                    running.* = false;
                }
            }
        }
    };
}

/// Calls a system using the provided world's data.
/// Arguments of the system will be references to the world's fields during execution.
///
/// World should be a pointer to the world.
/// System should be a function. All arguments of this function should be pointers.
///
/// Generics cannot be used. For this, create a wrapping generic struct that will create
/// a concrete function.
pub fn callSystem(world: anytype, comptime system: anytype) void {
    const fn_info = @typeInfo(@TypeOf(system));

    // check that the input is a function.
    if (fn_info != .Fn) {
        @compileError("System must be a function.");
    }

    // get the ptr types of all the system args.
    const types = comptime systemArgs(system);

    // get archetypes from world
    var archetypes = &@field(world, "archetypes");

    var world_pointers: std.meta.ArgsTuple(@TypeOf(system)) = undefined;
    comptime var i: usize = 0;
    comptime var at_arg: usize = 0;
    inline while (i < types.count) : (i += 1) {
        const ty = types.types[i];

        if (!ty.is_component) {
            // returns a pointer to a field of type t in world.
            const new_ptr = pointer_to_struct_type(ty.ty, world) orelse @panic("Provided world misses a field of the following type that the system requires: " ++ @typeName(ty.ty));
            world_pointers[at_arg] = new_ptr;
            at_arg += 1;
        } else {
            // iterating over query component types
            inline while (i < types.count and types.types[i].is_component) : (i += 1) {}
            // create query
            const query = @TypeOf(world_pointers[at_arg]).init(archetypes);
            world_pointers[at_arg] = query;
            at_arg += 1;
        }
    }

    const options = std.builtin.CallOptions{};
    @call(options, system, world_pointers);
}

const MAX_BORROWS = 128;
const ResBorrows = struct {
    types: [MAX_BORROWS]ResBorrow = undefined,
    count: usize = 0,
};

const ResBorrow = struct {
    ty: type,
    mut: bool,
    is_component: bool,
};

pub fn systemArgs(system: anytype) ResBorrows {
    const fn_info = @typeInfo(@TypeOf(system));
    comptime var borrows = ResBorrows{};
    inline for (fn_info.Fn.args) |arg| {
        const arg_type = arg.arg_type orelse @compileError("Argument has no type, are you using generic parameters?");
        const arg_info = @typeInfo(arg_type);
        if (arg_info == .Pointer) {
            borrows.types[borrows.count].ty = arg_info.Pointer.child;
            borrows.types[borrows.count].mut = !arg_info.Pointer.is_const;
            borrows.types[borrows.count].is_component = false;
            borrows.count += 1;
        } else if (arg_info == .Struct) {
            // Query(.{...}) struct
            const query_types = comptime_utils.innerTypesFromPointersTuple(arg_type.TYPES);
            const query_muts = comptime_utils.innerMutabilityFromPointersTuple(arg_type.TYPES);
            inline for (query_types) |ty, k| {
                // check if already exist
                comptime var dupe = false;
                comptime var j: usize = 0;
                while (j < borrows.count) : (j += 1) {
                    if (borrows.types[j].ty == ty) {
                        if (query_muts[k]) {
                            borrows.types[j].mut = true;
                        }
                        if (!borrows.types[j].is_component) {
                            @compileError("The same type is used in both world and archetypes! This is an error. Type: " ++ @typeName(borrows.types[j].ty));
                        }
                        dupe = true;
                    }
                }
                if (!dupe) {
                    // add because it doesn't exist already
                    borrows.types[borrows.count].ty = ty;
                    borrows.types[borrows.count].mut = query_muts[k];
                    borrows.types[borrows.count].is_component = true;
                    borrows.count += 1;
                }
            }
        } else {
            @compileError("System arguments must be pointers.");
        }
    }
    return borrows;
}

/// Returns a pointer to the first field of the provided runtime structure that has
/// the type Target, if any.
/// The structure should be a pointer to a struct.
fn pointer_to_struct_type(comptime Target: type, structure: anytype) ?*Target {
    //comptime const ptr_info = @typeInfo(@TypeOf(structure));
    //if (ptr_info != .Pointer) {
    //    @compileError("Expected a pointer to a struct.");
    //}

    //comptime const struct_info = @typeInfo(ptr_info.Pointer.child);
    const struct_info = @typeInfo(@TypeOf(structure.*));
    if (struct_info != .Struct) {
        @compileError("Expected a struct.");
    }

    inline for (struct_info.Struct.fields) |field| {
        if (field.field_type == Target) {
            return &@field(structure.*, field.name);
        }
    }
    return null;
}

// Tests
const TestComponentA = struct {
    a: i32,
};
const TestResourceA = struct {};

const TestArchetypesTypes = &[_][]const type{
    &[_]type{TestComponentA},
};
const TestArchetypes = Archetypes(TestArchetypesTypes);

const TestWorld = struct {
    archetypes: TestArchetypes,
    resource_a: TestResourceA,

    const S = @This();
    pub fn init() !S {
        return S{
            .archetypes = try TestArchetypes.init(std.testing.allocator),
            .resource_a = TestResourceA{},
        };
    }
    pub fn deinit(s: *S) void {
        s.archetypes.deinit();
    }
};

fn testSystemEmpty() void {}

fn testSystemResource(_: *TestResourceA) void {}

fn testSystemQuery(query: Query(.{*TestComponentA}, TestArchetypesTypes)) void {
    for (query.slices) |slice| {
        var i: usize = 0;
        while (i < slice[0].len) : (i += 1) {
            slice[0][i].a += 1;
        }
    }
}

test "Dispatch seq" {
    var world = try TestWorld.init();
    defer world.deinit();

    var dispatcher = Dispatcher(TestWorld, .{
        testSystemEmpty,
        testSystemResource,
        testSystemQuery,
    }){};
    dispatcher.run_seq(&world);
}

test "Dispatch par" {
    var world = try TestWorld.init();
    defer world.deinit();

    _ = try world.archetypes.insert(.{TestComponentA{
        .a = 0,
    }});

    var dispatcher = Dispatcher(TestWorld, .{
        testSystemEmpty,
        testSystemResource,
        testSystemQuery,
    }){};
    dispatcher.run_par(&world);

    try std.testing.expectEqual(@as(i32, 1), world.archetypes.archetypes.@"0".data.slice().items(.@"0")[0].a);
}
