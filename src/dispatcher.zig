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
        //pub fn run_par(self: *S, world: *world_ty) void {
        //}
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
pub fn callSystem(world: anytype, system: anytype) void {
    const fn_info = @typeInfo(@TypeOf(system));

    // check that the input is a function.
    if (fn_info != .Fn) {
        @compileError("System must be a function.");
    }

    // get the ptr types of all the system args.
    comptime var types: [fn_info.Fn.args.len]type = undefined;
    inline for (fn_info.Fn.args) |arg, i| {
        const arg_type = arg.arg_type orelse @compileError("Argument has no type, are you using generic parameters?");
        const arg_info = @typeInfo(arg_type);
        if (arg_info != .Pointer) {
            @compileError("System arguments must be pointers.");
        }
        types[i] = arg_info.Pointer.child;
    }

    var world_pointers: std.meta.ArgsTuple(@TypeOf(system)) = undefined;
    inline for (types) |t, i| {
        // returns a pointer to a field of type t in world.
        const new_ptr = pointer_to_struct_type(t, world) orelse @panic("Provided world misses a field of the following type that the system requires: " ++ @typeName(t));
        world_pointers[i] = new_ptr;
    }

    const options = std.builtin.CallOptions{};
    @call(options, system, world_pointers);
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
    pub fn deinit(self: *S) void {
        self.ecs.deinit();
    }
};

fn testSystemEmpty() void {}

fn testSystemResource(_: *TestResourceA) void {}

//fn testSystemQuery(_: Query(.{*TestComponentA})) void {
//}

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
