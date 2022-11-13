const std = @import("std");
const archetype = @import("./archetype.zig");
const Archetype = archetype.Archetype;

const testTypeSlices = &[_][]const type{
    &[_]type{ u32, u64 },
};

/// Converts a slice of slices of types into a slice of tuple types.
pub fn typeSliceToTuples(comptime type_slice: []const []const type) [type_slice.len]type {
    comptime var generated_tuples: [type_slice.len]type = undefined;
    inline for (type_slice) |inner_types, i| {
        generated_tuples[i] = std.meta.Tuple(inner_types);
    }
    return generated_tuples;
}

pub fn tupleSliceToArchetypeSlice(comptime tuple_ty: []const type) [tuple_ty.len]type {
    comptime var generated_storages: [tuple_ty.len]type = undefined;
    inline for (tuple_ty) |_, i| {
        generated_storages[i] = Archetype(tuple_ty[i]);
    }
    return generated_storages;
}

/// Instanciates a tuple containing archetype storages for all tuple types.
pub fn generateArchetypesStorage(comptime archetype_storage_ty: type, allocator: std.mem.Allocator) !archetype_storage_ty {
    var gen: archetype_storage_ty = undefined;
    inline for (std.meta.fields(archetype_storage_ty)) |field| {
        @field(gen, field.name) = try field.field_type.init(allocator);
    }
    return gen;
}

/// Frees the archetype tuples storage.
pub fn deinitArchetypesStorage(storage: anytype) void {
    const archetypes_types = @TypeOf(storage.*);
    inline for (std.meta.fields(archetypes_types)) |field| {
        @field(storage, field.name).deinit();
    }
}

/// Returns the number of fields inside of the provided type.
pub fn countFields(comptime types: anytype) usize {
    return std.meta.fields(@TypeOf(types)).len;
}

/// Converts a tuple pointers to a slice of the inner types.
pub fn pointersTupleToTypes(comptime tuple: anytype) [countFields(tuple)]type {
    const tuple_fields = std.meta.fields(@TypeOf(tuple));

    comptime var user_types: [countFields(tuple)]type = undefined;
    inline for (tuple_fields) |field, i| {
        const field_type = @field(tuple, field.name);
        const field_info = @typeInfo(field_type);
        // We have a tuple of types, where the types are pointers to type
        if (field_info != .Pointer) {
            @compileError("Iter arguments must be tuple of pointers. Got " ++ @typeName(field_type));
        }
        user_types[i] = field_info.Pointer.child;
    }
    return user_types;
}

pub fn pointersTupleToMuts(comptime tuple: anytype) [countFields(tuple)]bool {
    const tuple_fields = std.meta.fields(@TypeOf(tuple));

    comptime var user_types: [countFields(tuple)]bool = undefined;
    inline for (tuple_fields) |field, i| {
        const field_type = @field(tuple, field.name);
        const field_info = @typeInfo(field_type);
        // We have a tuple of types, where the types are pointers to type
        if (field_info != .Pointer) {
            @compileError("Iter arguments must be tuple of pointers. Got " ++ @typeName(field_type));
        }
        user_types[i] = !field_info.Pointer.is_const;
    }
    return user_types;
}

/// Converts a tuple of pointers to a slice of (const/non const) slices of those types.
/// For example, `pointersTupleToSlices(.{*A, *const B})` would return `.{[]A, []const B}`.
pub fn pointersTupleToSlices(comptime tuple: anytype) [countFields(tuple)]type {
    const tuple_fields = std.meta.fields(@TypeOf(tuple));

    comptime var converted_slice_types: [countFields(tuple)]type = undefined;
    inline for (tuple_fields) |field, i| {
        const field_type = @field(tuple, field.name);
        const field_info = @typeInfo(field_type);
        // We have a tuple of types, where the types are pointers to type
        if (field_info != .Pointer) {
            @compileError("Iter arguments must be tuple of pointers. Got " ++ @typeName(field_type));
        }
        if (field_info.Pointer.is_const) {
            converted_slice_types[i] = []const field_info.Pointer.child;
        } else {
            converted_slice_types[i] = []field_info.Pointer.child;
        }
    }
    return converted_slice_types;
}

/// For the provided list of allowed archetype type tuples, figures out how many the query will need access to.
pub fn count_compatible_slices(comptime archetype_types: []const []const type, comptime query_types: anytype) usize {
    const generated_tuples = typeSliceToTuples(archetype_types);

    comptime var slice_count = 0;
    // for self.archetypes find matching
    // increment slice_count each time you match
    inline for (generated_tuples) |archetype_tuple| {
        comptime var not_found = false;
        // For all types requested by the user
        inline for (query_types) |query_type| {
            // Search if the archetype contains it.
            comptime var found_type = false;
            inline for (std.meta.fields(archetype_tuple)) |archetype_field| {
                if (archetype_field.field_type == query_type) {
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

/// Provided a query tuple type, returns the tuple type of slices to those types.
pub fn output_tuple_ty(comptime types: anytype) type {
    return std.meta.Tuple(&pointersTupleToSlices(types));
}

/// Provided a query tuple type, returns a slice of archetype storage slices.
pub fn output_iter_ty(comptime archetype_types: []const []const type, comptime types: anytype) type {
    const inner_types = pointersTupleToTypes(types);
    const count = count_compatible_slices(archetype_types, inner_types);
    const tuple_ty = output_tuple_ty(types);
    return [count]tuple_ty;
}
