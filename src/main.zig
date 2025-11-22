const std = @import("std");
const zig_day_project = @import("zig_day_project");
const tracy = @import("zig_tracy");

const win32 = @import("zigwin32");
const gdi = win32.graphics.gdi; // For EnumDisplayMonitors
const foundation = win32.foundation; // For RECT, BOOL
const display = win32.devices.display; // For monitor brightness APIs
const zig = win32.zig; // For TRUE

fn utf16ToUtf8(allocator: std.mem.Allocator, wide: []const u16) ![]u8 {
    return try std.unicode.utf16LeToUtf8Alloc(allocator, wide);
}

const builtin = @import("builtin");
const dvui = @import("dvui");

const window_icon_png = @embedFile("zig-favicon.png");

// To be a dvui App:
// * declare "dvui_app"
// * expose the backend's main function
// * use the backend's log function
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            .icon = window_icon_png,
            .window_init_options = .{
                // Could set a default theme here
                // .theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = AppFrame,
    .initFn = AppInit,
    .deinitFn = AppDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var orig_content_scale: f32 = 1.0;
var warn_on_quit: bool = false;
var warn_on_quit_closing: bool = false;

// Runs before the first frame, after backend and dvui.Window.init()
// - runs between win.begin()/win.end()
pub fn AppInit(win: *dvui.Window) !void {
    orig_content_scale = win.content_scale;
    //try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    const allocator = std.heap.page_allocator;

    const callback = struct {
        fn monitorEnum(hMonitor: ?gdi.HMONITOR, _: ?gdi.HDC, _: ?*foundation.RECT, _: isize) callconv(.c) foundation.BOOL {
            if (hMonitor) |monitor| {
                std.log.info("Found monitor: {any}", .{monitor});

                var count: u32 = 0;

                if (display.GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, &count) != 0) {
                    std.log.info("Physical monitors: {}", .{count});

                    var monitors = allocator.alloc(display.PHYSICAL_MONITOR, count) catch {
                        std.log.err("Allocation failed", .{});
                        return win32.zig.TRUE;
                    };
                    defer std.heap.page_allocator.free(monitors);

                    if (display.GetPhysicalMonitorsFromHMONITOR(monitor, count, monitors.ptr) != 0) {
                        for (monitors[0..count]) |pm| {
                            const raw_name: []const u16 =
                                @as([]const u16, @ptrCast(@alignCast(&pm.szPhysicalMonitorDescription)))[0..128];
                            const name_len = std.mem.indexOfScalar(u16, raw_name, 0) orelse raw_name.len;
                            const wide_name = raw_name[0..name_len];

                            const name_utf8 = utf16ToUtf8(allocator, wide_name) catch {
                                std.log.warn("Name conversion failed", .{});
                                continue;
                            };
                            defer std.heap.page_allocator.free(name_utf8);

                            std.log.info("Name: {s}", .{name_utf8});

                            // var min: u32 = 0;
                            // var cur: u32 = 0;
                            // var max: u32 = 0;
                            // if (display.GetMonitorBrightness(pm.hPhysicalMonitor, &min, &cur, &max) != 0) {
                            //     std.log.info("Brightness: min={}, cur={}, max={}", .{ min, cur, max });
                            // } else {
                            //     std.log.warn("Brightness: Not supported", .{});
                            // }

                            var length: u32 = 0;
                            if (display.GetCapabilitiesStringLength(hMonitor, &length) == 0) {
                                const err = foundation.GetLastError();
                                std.log.err("GetCapabilitiesStringLength failed. Error={d}", .{err});
                            }

                            const buf = allocator.allocSentinel(u8, length, 0) catch {
                                std.log.err("Allocation failed", .{});
                                return 0;
                            };
                            defer allocator.free(buf);

                            if (display.CapabilitiesRequestAndCapabilitiesReply(hMonitor, buf.ptr, length) == 0) {
                                const err = foundation.GetLastError();
                                std.log.err("CapabilitiesRequestAndCapabilitiesReply failed. Error={d}", .{err});
                            }

                            const VCP_BRIGHTNESS: u8 = 0x10;

                            var vcp_type: display.MC_VCP_CODE_TYPE = undefined;
                            var current_value: u32 = 0;
                            var max_value: u32 = 0;

                            const ok: i32 = display.GetVCPFeatureAndVCPFeatureReply(
                                hMonitor,
                                VCP_BRIGHTNESS,
                                &vcp_type,
                                &current_value,
                                &max_value,
                            );

                            if (ok != 0) {
                                std.log.info(
                                    "VCP Brightness: current={d}, max={d}, type={d}\n",
                                    .{ current_value, max_value, @intFromEnum(vcp_type) },
                                );
                            } else {
                                const err = foundation.GetLastError();
                                std.log.err("Failed to get VCP brightness. Error code: {d}\n", .{err});
                            }

                            _ = display.DestroyPhysicalMonitor(pm.hPhysicalMonitor);
                        }
                    }
                }
            }
            return zig.TRUE;
        }
    }.monitorEnum;

    _ = gdi.EnumDisplayMonitors(null, null, callback, 0);

    if (false) {
        // If you need to set a theme based on the users preferred color scheme, do it here
        win.theme = switch (win.backend.preferredColorScheme() orelse .light) {
            .light => dvui.Theme.builtin.adwaita_light,
            .dark => dvui.Theme.builtin.adwaita_dark,
        };
    }
}

// Run as app is shutting down before dvui.Window.deinit()
pub fn AppDeinit() void {}

// Run each frame to do normal UI
pub fn AppFrame() !dvui.App.Result {
    return frame();
}

pub fn frame() !dvui.App.Result {
    var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
    scaler.deinit();

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
        defer hbox.deinit();

        var m = dvui.menu(@src(), .horizontal, .{});
        defer m.deinit();

        if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .tag = "first-focusable" })) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "Close Menu", .{}, .{ .expand = .horizontal }) != null) {
                m.close();
            }

            if (dvui.backend.kind != .web) {
                if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                    return .close;
                }
            }
        }
    }

    var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .font_style = .title_4 });
    const lorem = "This is a dvui.App example that can compile on multiple backends.";
    tl.addText(lorem, .{});
    tl.addText("\n\n", .{});
    tl.format("Current backend: {s}", .{@tagName(dvui.backend.kind)}, .{});
    if (dvui.backend.kind == .web) {
        tl.format(" : {s}", .{if (dvui.backend.wasm.wasm_about_webgl2() == 1) "webgl2" else "webgl (no mipmaps)"}, .{});
    }
    tl.deinit();

    var tl2 = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal });
    tl2.addText(
        \\DVUI
        \\- paints the entire window
        \\- can show floating windows and dialogs
        \\- rest of the window is a scroll area
    , .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is variable and adjusts as needed for input events and animations.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Framerate is capped by vsync.", .{});
    tl2.addText("\n\n", .{});
    tl2.addText("Cursor is always being set by dvui.", .{});
    tl2.addText("\n\n", .{});
    if (dvui.useFreeType) {
        tl2.addText("Fonts are being rendered by FreeType 2.", .{});
    } else {
        tl2.addText("Fonts are being rendered by stb_truetype.", .{});
    }
    tl2.deinit();

    const label = if (dvui.Examples.show_demo_window) "Hide Demo Window" else "Show Demo Window";
    if (dvui.button(@src(), label, .{}, .{ .tag = "show-demo-btn" })) {
        dvui.Examples.show_demo_window = !dvui.Examples.show_demo_window;
    }

    if (dvui.button(@src(), "Debug Window", .{}, .{})) {
        dvui.toggleDebugWindow();
    }

    {
        var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
        defer hbox.deinit();
        dvui.label(@src(), "Pinch Zoom or Scale", .{}, .{});
        if (dvui.buttonIcon(@src(), "plus", dvui.entypo.plus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale *= 1.1;
        }

        if (dvui.buttonIcon(@src(), "minus", dvui.entypo.minus, .{}, .{}, .{})) {
            dvui.currentWindow().content_scale /= 1.1;
        }

        if (dvui.currentWindow().content_scale != orig_content_scale) {
            if (dvui.button(@src(), "Reset Scale", .{}, .{})) {
                dvui.currentWindow().content_scale = orig_content_scale;
            }
        }
    }

    if (dvui.backend.kind != .web) {
        _ = dvui.checkbox(@src(), &warn_on_quit, "Warn on Quit", .{});

        if (warn_on_quit) {
            if (warn_on_quit_closing) return .close;

            const wd = dvui.currentWindow().data();
            for (dvui.events()) |*e| {
                if (!dvui.eventMatchSimple(e, wd)) continue;

                if ((e.evt == .window and e.evt.window.action == .close) or (e.evt == .app and e.evt.app.action == .quit)) {
                    e.handle(@src(), wd);

                    const warnAfter: dvui.DialogCallAfterFn = struct {
                        fn warnAfter(_: dvui.Id, response: dvui.enums.DialogResponse) !void {
                            if (response == .ok) warn_on_quit_closing = true;
                        }
                    }.warnAfter;

                    dvui.dialog(@src(), .{}, .{ .message = "Really Quit?", .cancel_label = "Cancel", .callafterFn = warnAfter });
                }
            }
        }
    }

    // look at demo() for examples of dvui widgets, shows in a floating window
    dvui.Examples.demo();

    return .ok;
}

test "tab order" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    try dvui.testing.expectNotFocused("first-focusable");

    try dvui.testing.pressKey(.tab, .none);
    try dvui.testing.settle(frame);

    try dvui.testing.expectFocused("first-focusable");
}

test "open example window" {
    var t = try dvui.testing.init(.{});
    defer t.deinit();

    try dvui.testing.settle(frame);

    // FIXME: The global show_demo_window variable makes tests order dependent
    dvui.Examples.show_demo_window = false;

    try std.testing.expect(dvui.tagGet(dvui.Examples.demo_window_tag) == null);

    try dvui.testing.moveTo("show-demo-btn");
    try dvui.testing.click(.left);
    try dvui.testing.settle(frame);

    try dvui.testing.expectVisible(dvui.Examples.demo_window_tag);
}

// disabling snapshot tests until we figure out a better (less sensitive) way of doing them
//test "snapshot" {
//    // snapshot tests are unstable
//    var t = try dvui.testing.init(.{});
//    defer t.deinit();
//
//    // FIXME: The global show_demo_window variable makes tests order dependent
//    dvui.Examples.show_demo_window = false;
//
//    try dvui.testing.settle(frame);
//
//    // Try swapping the names of ./snapshots/app.zig-test.snapshot-X.png
//    try t.snapshot(@src(), frame);
//
//    try dvui.testing.pressKey(.tab, .none);
//    try dvui.testing.settle(frame);
//
//    try t.snapshot(@src(), frame);
//}

// pub fn main() !void {
//     // Prints to stderr, ignoring potential errors.
//     std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
//     try zig_day_project.bufferedPrint();
// }

// test "simple test" {
//     const gpa = std.testing.allocator;
//     var list: std.ArrayList(i32) = .empty;
//     defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
//     try list.append(gpa, 42);
//     try std.testing.expectEqual(@as(i32, 42), list.pop());
// }
//
// test "fuzz example" {
//     const Context = struct {
//         fn testOne(context: @This(), input: []const u8) anyerror!void {
//             _ = context;
//             // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
//             try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
//         }
//     };
//     try std.testing.fuzz(Context{}, Context.testOne, .{});
// }

// const std = @import("std");
// const win = @cImport({
//     @cInclude("windows.h");
//     @cInclude("physicalmonitorenumerationapi.h");
//     @cInclude("lowlevelmonitorconfigurationapi.h");
// });
//
// const MONITORENUMPROC = fn (
//     hMonitor: win.HMONITOR,
//     hdc: win.HDC,
//     lprcMonitor: [*c]win.RECT,
//     dwData: win.LPARAM,
// ) callconv(.c) c_int;
//
// fn monitorEnumProc(
//     hMonitor: win.HMONITOR,
//     _: win.HDC,
//     _: [*c]win.RECT,
//     _: win.LPARAM,
// ) callconv(.c) c_int {
//     var monitor_count: u32 = 0;
//     if (win.GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &monitor_count) == 0) {
//         const err = win.GetLastError();
//         std.debug.print("  Failed to get physical monitor count. Error code: {}\n", .{err});
//         return 1;
//     }
//
//     const monitors = std.heap.page_allocator.alloc(win.PHYSICAL_MONITOR, monitor_count) catch {
//         std.debug.print("  Failed to allocate monitor array.\n", .{});
//         return 1;
//     };
//     defer std.heap.page_allocator.free(monitors);
//
//     if (win.GetPhysicalMonitorsFromHMONITOR(hMonitor, monitor_count, monitors.ptr) == 0) {
//         const err = win.GetLastError();
//         std.debug.print("  Failed to get physical monitors. Error code: {}\n", .{err});
//         return 1;
//     }
//
//     for (monitors[0..monitor_count]) |monitor| {
//         const desc_slice = monitor.szPhysicalMonitorDescription[0..];
//         const utf8_desc = std.unicode.utf16LeToUtf8Alloc(std.heap.page_allocator, desc_slice) catch {
//             std.debug.print("  Failed to convert monitor description to UTF-8.\n", .{});
//             continue;
//         };
//         defer std.heap.page_allocator.free(utf8_desc);
//
//         std.debug.print("Monitor: {s}\n", .{utf8_desc});
//
//         const VCP_BRIGHTNESS: u8 = 0x10;
//         var current_value: u32 = 0;
//         var max_value: u32 = 0;
//         var vcp_type: win.MC_VCP_CODE_TYPE = undefined;
//
//         if (win.GetVCPFeatureAndVCPFeatureReply(
//             monitor.hPhysicalMonitor,
//             VCP_BRIGHTNESS,
//             &vcp_type,
//             &current_value,
//             &max_value,
//         ) != 0) {
//             std.debug.print("  VCP Brightness: current={d}, max={d}, type={d}\n", .{
//                 current_value, max_value, vcp_type,
//             });
//         } else {
//             const err = win.GetLastError();
//             std.debug.print("  Failed to get VCP brightness. Error code: {}\n", .{err});
//         }
//     }
//
//     _ = win.DestroyPhysicalMonitors(monitor_count, monitors.ptr);
//     return 1;
// }
//
// pub fn main() !void {
//     std.debug.print("Enumerating connected monitors...\n", .{});
//
//     const success = win.EnumDisplayMonitors(
//         null,
//         null,
//         monitorEnumProc,
//         0,
//     );
//
//     if (success == 0) {
//         const err = win.GetLastError();
//         std.debug.print("Failed to enumerate monitors. Error code: {}\n", .{err});
//     }
// }
