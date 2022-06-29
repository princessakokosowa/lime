const std = @import("std");
const assert = std.debug.assert;

const zwin32 = @import("zwin32");
const win32 = zwin32.base;
const direct3d12 = zwin32.d3d12;

// @NOTE
// Bindings to WinAPI sometimes look miserable (or I just don't yet understand where the various
// constants are situated). For now, I hardcode some of the constants, but tag them somewhere so
// that I know where to change them in the future.
//
// Most of TODOs here concern this.
//
//     princessakokosowa, 29 June 2022

const Window = struct {
    window: win32.HWND,

    is_minimized: bool = false,
    is_maximized: bool = false,
    is_close_requested: bool = false,

    // @TODO
    // Add ImGui support at some point.
    //
    // is_imgui_initialized: bool = false,

    // @TODO
    // 0xFE is VK_OEM_CLEAR
    is_key_down: [0xFE]bool = undefined,
    is_previous_key_down: [0xFE]bool = undefined,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, window_width: i32, window_height: i32, window_title: ?[*:0]const u8) !*Self {
        var self = try allocator.create(Self);

        var window_class: win32.user32.WNDCLASSEXA = .{
            .cbSize = @sizeOf(win32.user32.WNDCLASSEXA),
            .style = win32.user32.CS_HREDRAW | win32.user32.CS_VREDRAW,
            .lpfnWndProc = proc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = @ptrCast(win32.HINSTANCE, win32.kernel32.GetModuleHandleW(null)),
            .hIcon = null,

            // @TODO
            // 32512 is IDC_ARROW
            // @intCast(isize, @ptrToInt(self)) is (LONG_PTR)(self), in C style
            .hCursor = win32.LoadCursorA(null, @intToPtr(win32.LPCSTR, 32512)),
            .hbrBackground = null,
            .lpszMenuName = null,
            .lpszClassName = window_title orelse "lime",
            .hIconSm = null,
        };

        _ = try win32.user32.registerClassExA(&window_class);

        var window_rect: win32.RECT = .{
            .left = 0,
            .top = 0,
            .right = @intCast(i32, window_width),
            .bottom = @intCast(i32, window_height),
        };

        const window_rect_adjustment_parameters = win32.user32.WS_OVERLAPPED | win32.user32.WS_SYSMENU | win32.user32.WS_CAPTION | win32.user32.WS_MINIMIZEBOX;
        const window_style_parameters = window_rect_adjustment_parameters | win32.user32.WS_VISIBLE;

        try win32.user32.adjustWindowRectEx(&window_rect, window_rect_adjustment_parameters, false, 0);

        const window = try win32.user32.createWindowExA(
            0,
            window_title orelse "lime",
            window_title orelse "lime",
            window_style_parameters,
            win32.user32.CW_USEDEFAULT,
            win32.user32.CW_USEDEFAULT,
            window_rect.right - window_rect.left,
            window_rect.bottom - window_rect.top,
            null,
            null,
            @ptrCast(win32.HINSTANCE, win32.kernel32.GetModuleHandleW(null)),
            null,
        );

        // @TODO
        // -21                              is GWLP_USERDATA
        // @intCast(isize, @ptrToInt(self)) is (LONG_PTR)(self), in C style
        _ = win32.user32.SetWindowLongPtrA(window, -21,              @intCast(isize, @ptrToInt(self)));
        _ = win32.user32.ShowWindow(window, win32.user32.SW_SHOWDEFAULT);

        self.* = .{
            .window = window,
            .is_minimized = false,
            .is_maximized = false,
            .is_close_requested = false,
            .is_key_down = undefined,
            .is_previous_key_down = undefined,
        };

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    fn proc(
        window: win32.HWND,
        message: win32.UINT,
        wparam: win32.WPARAM,
        lparam: win32.LPARAM,
    ) callconv(win32.WINAPI) win32.LRESULT {
        switch (message) {
            win32.user32.WM_KEYDOWN => {
                if (wparam == win32.VK_ESCAPE) {
                    win32.user32.PostQuitMessage(0);
                }
            },
            win32.user32.WM_DESTROY => {
                win32.user32.PostQuitMessage(0);
            },
            else => {
                return win32.user32.defWindowProcA(window, message, wparam, lparam);
            },
        }

        return 0;
    }

    pub fn handleEvents() bool {
        var message = std.mem.zeroes(win32.user32.MSG);

        while (win32.user32.peekMessageA(&message, null, 0, 0, win32.user32.PM_REMOVE) catch false) {
            _ = win32.user32.translateMessage(&message);
            _ = win32.user32.dispatchMessageA(&message);

            if (message.message == win32.user32.WM_QUIT) {
                return false;
            }
        }

        return true;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var window = try Window.init(allocator, 1280, 720, null);
    defer window.deinit(allocator);

    while (Window.handleEvents()) {
       // loooooooooop
    }
}
