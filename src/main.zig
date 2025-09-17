const std = @import("std");
const dvui = @import("dvui");

const win = @cImport({
    @cInclude("windows.h");
    @cInclude("physicalmonitorenumerationapi.h");
    @cInclude("lowlevelmonitorconfigurationapi.h");
});

const MONITORENUMPROC = fn (
    hMonitor: win.HMONITOR,
    hdc: win.HDC,
    lprcMonitor: [*c]win.RECT,
    dwData: win.LPARAM,
) callconv(.c) c_int;

fn monitorEnumProc(
    hMonitor: win.HMONITOR,
    _: win.HDC,
    _: [*c]win.RECT,
    _: win.LPARAM,
) callconv(.c) c_int {
    var monitor_count: u32 = 0;
    if (win.GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &monitor_count) == 0) {
        const err = win.GetLastError();
        std.debug.print("  Failed to get physical monitor count. Error code: {}\n", .{err});
        return 1;
    }

    const monitors = std.heap.page_allocator.alloc(win.PHYSICAL_MONITOR, monitor_count) catch {
        std.debug.print("  Failed to allocate monitor array.\n", .{});
        return 1;
    };
    defer std.heap.page_allocator.free(monitors);

    if (win.GetPhysicalMonitorsFromHMONITOR(hMonitor, monitor_count, monitors.ptr) == 0) {
        const err = win.GetLastError();
        std.debug.print("  Failed to get physical monitors. Error code: {}\n", .{err});
        return 1;
    }

    for (monitors[0..monitor_count]) |monitor| {
        const desc_slice = monitor.szPhysicalMonitorDescription[0..];
        const utf8_desc = std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, desc_slice) catch {
            std.debug.print("  Failed to convert monitor description to UTF-8.\n", .{});
            continue;
        };
        defer std.heap.page_allocator.free(utf8_desc);

        std.debug.print("Monitor: {s}\n", .{utf8_desc});

        const VCP_BRIGHTNESS: u8 = 0x10;
        var current_value: u32 = 0;
        var max_value: u32 = 0;
        var vcp_type: win.MC_VCP_CODE_TYPE = undefined;

        if (win.GetVCPFeatureAndVCPFeatureReply(
            monitor.hPhysicalMonitor,
            VCP_BRIGHTNESS,
            &vcp_type,
            &current_value,
            &max_value,
        ) != 0) {
            std.debug.print("  VCP Brightness: current={d}, max={d}, type={d}\n", .{
                current_value, max_value, vcp_type,
            });
        } else {
            const err = win.GetLastError();
            std.debug.print("  Failed to get VCP brightness. Error code: {}\n", .{err});
        }
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
        const err = win.GetLastError();
        std.debug.print("Failed to enumerate monitors. Error code: {}\n", .{err});
    }

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    //
    // var app = try dvui.App.init(allocator, .{
    //     .backend = dvui.backends.dx11,
    //     .title = "Monitor Brightness Control",
    //     .width = 800,
    //     .height = 600,
    // });
    // defer app.deinit();
    //
    // while (try app.beginFrame()) {
    //     var vbox = dvui.box(@src(), .{ .dir = .vertical }, .{});
    //     defer vbox.deinit();
    //
    //     dvui.label(@src(), "Monitor Brightness Control", .{}, .{});
    //     dvui.separator();
    //
    //     for (0..3) |i| {
    //         var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .id_extra = i });
    //         defer hbox.deinit();
    //
    //         dvui.label(@src(), "Monitor {d}", .{i}, .{});
    //         var brightness: f32 = 0.5;
    //         _ = dvui.sliderEntry(@src(), "Brightness", .{ .value = &brightness, .min = 0.0, .max = 1.0 }, .{});
    //     }
    // }
}
