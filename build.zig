const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const dvui_dep = b.dependency("dvui", .{});

    // Use b.path() to create a LazyPath from a string
    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // ✅ Add dvui to the root module
    // root_mod.addImport("dvui", dvui_dep.module("root"));

    const exe = b.addExecutable(.{
        .name = "monitor_brightness_control_panel_app",
        .root_module = root_mod,
    });

    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("dxva2");

    // exe.setSubsystem(.Console, .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    b.default_step.dependOn(&run_cmd.step);
}
