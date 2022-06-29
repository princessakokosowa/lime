const std = @import("std");
const assert = std.debug.assert;

const zwin32 = @import("zwin32");
const win32 = zwin32.base;
const dxgi = zwin32.dxgi;
const direct3d12 = zwin32.d3d12;
const direct3d12d = zwin32.d3d12d;
const HResultError = zwin32.HResultError;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const hrErrorOnFail = zwin32.hrErrorOnFail;

// @NOTE
// Bindings to WinAPI sometimes look miserable (or I just don't yet understand where the various
// constants are situated). For now, I hardcode some of the constants, but tag them somewhere so
// that I know where to change them in the future.
//
// Most of TODOs here concern this.
//
// Also, some of the procedures from WinAPI are there in the standard library, but some (e.g.
// LoadCursorA) are not, hence the different naming style.
//
//     princessakokosowa, 29 June 2022

const Window = struct {
    const Flags = i32;

    pub const maximize_window: Flags = 1 << 0;

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

    pub fn init(allocator: std.mem.Allocator, window_width: i32, window_height: i32, window_title: ?[*:0]const u8, flags: Flags) !*Self {
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
        // -21 is GWLP_USERDATA
        _ = try win32.user32.setWindowLongPtrA(window, -21, @intCast(isize, @ptrToInt(self)));
        _ = win32.user32.showWindow(window, if ((flags & maximize_window) != 0) win32.user32.SW_SHOWMAXIMIZED else win32.user32.SW_SHOWDEFAULT);

        self.* = .{
            .window = window,
        };

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        // try win32.user32.destroyWindow(self.window);
        _ = win32.user32.DestroyWindow(self.window);
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
                    win32.user32.postQuitMessage(0);
                }
            },
            win32.user32.WM_DESTROY => {
                win32.user32.postQuitMessage(0);
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

const Context = struct {
    const Flags = i32;

    pub const enable_debug_layer: Flags = 1 << 0;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, window: *Window, flags: Flags) !*Self {
        var self = try allocator.create(Self);

        if ((flags & enable_debug_layer) != 0) {
            var debug_controller: ?*direct3d12d.IDebug1 = null;
            _ = direct3d12.D3D12GetDebugInterface(&direct3d12d.IID_IDebug1, @ptrCast(*?*anyopaque, &debug_controller));
            
            if (debug_controller) |debug_controller_| {
                debug_controller_.EnableDebugLayer();
                // debug_controller_.SetEnableGPUBasedValidation(win32.TRUE);
                debug_controller_.SetEnableSynchronizedCommandQueueValidation(win32.TRUE);
                _ = debug_controller_.Release();
            }
        }

        const factory = blk: {
            var factory: *dxgi.IFactory6 = undefined;

            hrPanicOnFail(dxgi.CreateDXGIFactory2(
                if ((flags & enable_debug_layer) != 0) dxgi.CREATE_FACTORY_DEBUG else 0,
                &dxgi.IID_IFactory6,
                @ptrCast(*?*anyopaque, &factory),
            ));

            break :blk factory;
        };
        defer _ = factory.Release();

        const device = blk: {
            // That's the maximum number of adapters you can have on Windows.
            const adapters_count = 8;
            var adapters: [adapters_count]?*dxgi.IAdapter1 = undefined;
            var adapter_descs: [adapters_count]dxgi.ADAPTER_DESC1 = undefined;
            var adapter_scores: [adapters_count]i32 = undefined;

            var i: usize = 0;
            while (i < adapters_count) : (i += 1) {
                var adapter: ?*dxgi.IAdapter1 = null;
                var adapter_desc: dxgi.ADAPTER_DESC1 = undefined;

                if (factory.EnumAdapters1(@intCast(u32, i), &adapter) != win32.S_OK) {
                    break;
                }

                var adapter_score: i32 = 0;
                if (adapter) |adapter_| {
                    _ = adapter_.GetDesc1(&adapter_desc); // != win32.S_OK, but at this point, there's no use.
    
                    if ((adapter_desc.Flags & dxgi.ADAPTER_FLAG_SOFTWARE) != 0) {
                        adapter_score = 0;
                    } else {
                        switch (adapter_desc.VendorId) {
                            0x10DE => adapter_score = 3,
                            0x1002 => adapter_score = 2,
                            else => adapter_score = 1,
                        }
    
                        var j: usize = 0;
                        while (j < i) : (j += 1) {
                            const has_higher_score = adapter_score > adapter_scores[j];
                            const has_the_same_score = adapter_score == adapter_scores[j];
                            const has_more_dedicated_video_memory = has_the_same_score and adapter_desc.DedicatedVideoMemory > adapter_descs[j].DedicatedVideoMemory;
    
                            if (has_higher_score or has_more_dedicated_video_memory) {
                                break;
                            }
                        }
    
                        var k = i;
                        while (k > j) : (k -= 1) {
                            adapters[k] = adapters[k - 1];
                            adapter_descs[k] = adapter_descs[k - 1];
                            adapter_scores[k] = adapter_scores[k - 1];
                        }
    
                        adapters[j] = adapter_;
                        adapter_descs[j] = adapter_desc;
                        adapter_scores[j] = adapter_score;
                    }
                }
            }

            defer {
                for (adapters) |adapter| {
                    if (adapter) |adapter_| {
                        _ = adapter_.Release();
                    }
                }
            }

            var device: *direct3d12.IDevice9 = undefined;

            for (adapters) |adapter| {
                if (direct3d12.D3D12CreateDevice(if (adapter) |adapter_| @ptrCast(*win32.IUnknown, adapter_) else null, .FL_12_1, &direct3d12.IID_IDevice9, @ptrCast(*?*anyopaque, &device)) == win32.S_OK) {
                    break;
                }
            }

            break :blk device;
        };

        _ = device;
        _ = window;
        _ = flags;

        // self.* = .{
        // };

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const window_flags: Window.Flags = 0;
    var window = try Window.init(allocator, 1280, 720, null, window_flags);
    // defer try window.deinit(allocator);
    defer window.deinit(allocator);

    const context_flags: Context.Flags = Context.enable_debug_layer;
    var context = try Context.init(allocator, window, context_flags);
    defer context.deinit(allocator);

    _ = window;
    _ = context;

    while (Window.handleEvents()) {
       // loooooooooop
    }
}
