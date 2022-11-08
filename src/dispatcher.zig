const std = @import("std");
const Archetypes = @import("archetypes.zig").Archetypes;
const Query = @import("query.zig").Query;
pub fn Dispatcher(comptime world_ty: type, systems: anytype) type {
    return struct {
        const S = @This();
        pub fn run_seq(_: *S, world: *world_ty) void {
            inline for (std.meta.fields(@TypeOf(systems))) |system_tuple_field| {
                const system = @field(systems, system_tuple_field.name);
                callSystem(world, system);
            }
        }
        pub fn run_par(s: *S, world: *world_ty) void {
            _ = s;
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
                inline for (system_borrows) |borrow| {
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
            for (system_running) |*running, i| {
                if (running.*) {
                    await system_frames[i];
                    running.* = false;
                }
            }

            // debug ensure all system did run and are not running anymore
            // TODO
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

    var world_pointers: std.meta.ArgsTuple(@TypeOf(system)) = undefined;
    inline for (types) |t, i| {
        // returns a pointer to a field of type t in world.
        const new_ptr = pointer_to_struct_type(t.ty, world) orelse @panic("Provided world misses a field of the following type that the system requires: " ++ @typeName(@TypeOf(t)));
        world_pointers[i] = new_ptr;
    }

    const options = std.builtin.CallOptions{};
    @call(options, system, world_pointers);
}

const ResBorrow = struct {
    ty: type,
    mut: bool,
};

pub fn systemArgs(system: anytype) [@typeInfo(@TypeOf(system)).Fn.args.len]ResBorrow {
    const fn_info = @typeInfo(@TypeOf(system));
    comptime var types: [fn_info.Fn.args.len]ResBorrow = undefined;
    inline for (fn_info.Fn.args) |arg, i| {
        const arg_type = arg.arg_type orelse @compileError("Argument has no type, are you using generic parameters?");
        const arg_info = @typeInfo(arg_type);
        if (arg_info != .Pointer) {
            @compileError("System arguments must be pointers.");
        }
        types[i].ty = arg_info.Pointer.child;
        types[i].mut = !arg_info.Pointer.is_const;
    }
    return types;
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
const TestArchetypes = Archetypes(&[_][]const type{
    &[_]type{TestComponentA},
});

const TestWorld = struct {
    ecs: TestArchetypes,
    resource_a: TestResourceA,

    const S = @This();
    pub fn init() !S {
        return S{
            .ecs = try TestArchetypes.init(std.testing.allocator),
            .resource_a = TestResourceA{},
        };
    }
    pub fn deinit(s: *S) void {
        s.ecs.deinit();
    }
};

fn testSystemEmpty() void {}

fn testSystemResource(_: *TestResourceA) void {}

fn testSystemQuery(_: Query(.{*TestComponentA})) void {}

test "Dispatch seq" {
    var world = try TestWorld.init();
    defer world.deinit();

    var dispatcher = Dispatcher(TestWorld, .{
        testSystemEmpty,
        testSystemResource,
        //testSystemQuery,
    }){};
    dispatcher.run_seq(&world);
}

test "Dispatch par" {
    var world = try TestWorld.init();
    defer world.deinit();

    var dispatcher = Dispatcher(TestWorld, .{
        testSystemEmpty,
        testSystemResource,
        //testSystemQuery,
    }){};
    dispatcher.run_par(&world);
}
