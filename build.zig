const std = @import("std");

pub fn build(b: *std.Build) void {
    const allocator = b.allocator;
    const windows_sdk_path = std.process.getEnvVarOwned(allocator, "ZIG_WINDOWS_SDK_PATH") catch {
        std.debug.print("❌ ZIG_WINDOWS_SDK_PATH is not set.\n", .{});
        return;
    };
    std.debug.print("✅ ZIG_WINDOWS_SDK_PATH = {s}\n", .{windows_sdk_path});

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "monitor_brightness_control_panel",
        .root_source_file = .{ .cwd_relative = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("dxva2");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    b.step("run", "Run the monitor brightness control panel").dependOn(&run_cmd.step);
}
