const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("archecs", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);
    const entity_tests = b.addTest("src/entity.zig");
    entity_tests.setBuildMode(mode);
    const archetype_tests = b.addTest("src/archetype.zig");
    archetype_tests.setBuildMode(mode);
    const archetypes_tests = b.addTest("src/archetypes.zig");
    archetypes_tests.setBuildMode(mode);
    const dispatcher_tests = b.addTest("src/dispatcher.zig");
    dispatcher_tests .setBuildMode(mode);
    const comptime_utils_tests = b.addTest("src/comptime_utils.zig");
    comptime_utils_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&entity_tests.step);
    test_step.dependOn(&archetype_tests.step);
    test_step.dependOn(&archetypes_tests.step);
    test_step.dependOn(&dispatcher_tests.step);
    test_step.dependOn(&comptime_utils_tests.step);
}
