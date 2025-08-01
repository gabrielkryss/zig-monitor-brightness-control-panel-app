const std = @import("std");

// Unified import block
const win = @cImport({
    @cInclude("windows.h");
    @cInclude("physicalmonitorenumerationapi.h");
    @cInclude("highlevelmonitorconfigurationapi.h");
});

// Callback function type expected by EnumDisplayMonitors
const MONITORENUMPROC = fn (
    hMonitor: win.HMONITOR,
    hdc: win.HDC,
    lprcMonitor: [*c]win.RECT,
    dwData: win.LPARAM,
) callconv(.C) c_int;

// Callback implementation
fn monitorEnumProc(
    hMonitor: win.HMONITOR,
    _: win.HDC,
    _: [*c]win.RECT,
    _: win.LPARAM,
) callconv(.C) c_int {
    var monitor_count: u32 = 0;
    if (win.GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &monitor_count) == 0) {
        std.debug.print("  Failed to get physical monitor count.\n", .{});
        return 1;
    }

    const monitors = std.heap.page_allocator.alloc(win.PHYSICAL_MONITOR, monitor_count) catch {
        std.debug.print("  Failed to allocate monitor array.\n", .{});
        return 1;
    };
    defer std.heap.page_allocator.free(monitors);

    if (win.GetPhysicalMonitorsFromHMONITOR(hMonitor, monitor_count, monitors.ptr) == 0) {
        std.debug.print("  Failed to get physical monitors.\n", .{});
        return 1;
    }

    for (monitors[0..monitor_count]) |monitor| {
        const utf8_desc = std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, &monitor.szPhysicalMonitorDescription) catch {
            std.debug.print("  Failed to convert monitor description to UTF-8.\n", .{});
            continue;
        };
        defer std.heap.page_allocator.free(utf8_desc);

        std.debug.print("Monitor: {s}\n", .{utf8_desc});

        var caps: u32 = 0;
        var colorTemps: u32 = 0;

        if (win.GetMonitorCapabilities(monitor.hPhysicalMonitor, &caps, &colorTemps) == 0) {
            std.debug.print("  Failed to get monitor capabilities.\n", .{});
            continue;
        }

        const supportsBrightness = (caps & win.MC_CAPS_BRIGHTNESS) != 0;
        if (!supportsBrightness) {
            std.debug.print("  Brightness control not supported.\n", .{});
            continue;
        }

        var min: u32 = 0;
        var cur: u32 = 0;
        var max: u32 = 0;

        if (win.GetMonitorBrightness(monitor.hPhysicalMonitor, &min, &cur, &max) == 0) {
            std.debug.print("  Failed to get brightness values.\n", .{});
            continue;
        }

        std.debug.print("  Brightness supported: min={d}, current={d}, max={d}\n", .{ min, cur, max });
    }

    _ = win.DestroyPhysicalMonitors(monitor_count, monitors.ptr);
    return 1;
}

pub fn main() !void {
    std.debug.print("Enumerating connected monitors...\n", .{});

    const success = win.EnumDisplayMonitors(
        null,
        null,
        monitorEnumProc,
        0,
    );

    if (success == 0) {
        std.debug.print("Failed to enumerate monitors.\n", .{});
    }
}
