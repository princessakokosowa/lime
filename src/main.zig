const std = @import("std");
const assert = std.debug.assert;

const zwin32 = @import("zwin32");
const win32 = zwin32.base;
const direct3d12 = zwin32.d3d12;

fn processMessages(
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

pub fn handleWindowEvents() bool {
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

pub fn main() !void {
    var instance = win32.kernel32.GetModuleHandleW(null);
    var cursor = win32.LoadCursorA(@ptrCast(win32.HINSTANCE, instance), @intToPtr(win32.LPCSTR, 32512));
    //                                                                                          ^^^^^ IDC_ARROW

    var name = "lime";

    const window_class = win32.user32.WNDCLASSEXA{
        .style = 0,
        .lpfnWndProc = processMessages,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = @ptrCast(win32.HINSTANCE, instance),
        .hIcon = null,
        .hCursor = cursor,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = name,
        .hIconSm = null,
    };

     _ = try win32.user32.registerClassExA(&window_class);

    var rectangle = win32.RECT{
        .left = 0,
        .top = 0,
        .right = @intCast(i32, 1280),
        .bottom = @intCast(i32, 720),
    };

    const rectangle_adjustment_parameters = win32.user32.WS_OVERLAPPED | win32.user32.WS_SYSMENU | win32.user32.WS_CAPTION | win32.user32.WS_MINIMIZEBOX;

    // const is_required_size_of_the_window_rectangle_calculated = adjustWindowRect(&rectangle, rectangle_adjustment_parameters, false);
    // assert(is_required_size_of_the_window_rectangle_calculated);

    try win32.user32.adjustWindowRectEx(&rectangle, rectangle_adjustment_parameters, false, 0);


    const window_style_parameters = rectangle_adjustment_parameters | win32.user32.WS_VISIBLE;

    const window = try win32.user32.createWindowExA(
        0, // dwExStyle
        name,
        name,
        window_style_parameters,
        win32.user32.CW_USEDEFAULT,
        win32.user32.CW_USEDEFAULT,
        rectangle.right - rectangle.left,
        rectangle.bottom - rectangle.top,
        null, // hWndParent
        null, // hMenu
        window_class.hInstance,
        null, // lpParam
    );

    _ = window;

    while (handleWindowEvents()) {
    }
}
