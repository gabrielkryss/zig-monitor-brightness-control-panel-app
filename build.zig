const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Use b.path() to create a LazyPath from a string
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "monitor_enum",
        .root_module = root_mod,
    });

    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("dxva2");

    // exe.setSubsystem(.Console, .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    b.default_step.dependOn(&run_cmd.step);
}
