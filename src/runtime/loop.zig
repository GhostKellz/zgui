const std = @import("std");

pub const zigzag = @import("zigzag");
pub const wzl = @import("wzl");
pub const zsync = @import("zsync");
const AsyncBridge = @import("async.zig").AsyncBridge;
const events = @import("events.zig");

/// Runtime coordinates the zigzag event loop and Wayland dispatch.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    event_loop: zigzag.EventLoop,
    client: wzl.Client,
    zsync_runtime: ?*zsync.runtime.Runtime,
    async_bridge: AsyncBridge,
    events: events.Queue,
    wayland_watch_fd: ?i32 = null,
    pending_wayland_dispatch: bool = false,
    failure: ?Error = null,

    pub const Error = error{
        WaylandDispatchFailed,
        WaylandConnectionClosed,
        WaylandHangup,
    } || std.mem.Allocator.Error;

    pub const Options = struct {
        event_loop: zigzag.Options = .{},
        auto_roundtrip: bool = true,
        zsync_runtime: ?*zsync.runtime.Runtime = null,
        enable_async: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, options: Options) !*Runtime {
        var zsync_runtime_ptr = options.zsync_runtime;
        var owns_zsync_runtime = false;
        if (options.enable_async and zsync_runtime_ptr == null) {
            zsync_runtime_ptr = try zsync.runtime.Runtime.init(allocator, .{});
            owns_zsync_runtime = true;
            errdefer if (zsync_runtime_ptr) |rt| rt.deinit();
        }

        var event_loop = try zigzag.EventLoop.init(allocator, options.event_loop);
        errdefer event_loop.deinit();

        var client = try wzl.Client.init(allocator, .{ .runtime = zsync_runtime_ptr });
        errdefer client.deinit();

        try client.connect();

        if (options.auto_roundtrip) {
            _ = try client.getRegistry();
            try client.roundtrip();
        }

        const runtime = try allocator.create(Runtime);
        errdefer allocator.destroy(runtime);

        const async_bridge = if (options.enable_async or zsync_runtime_ptr != null)
            AsyncBridge.init(allocator, zsync_runtime_ptr, owns_zsync_runtime)
        else
            AsyncBridge.disabled(allocator);

        runtime.* = Runtime{
            .allocator = allocator,
            .event_loop = event_loop,
            .client = client,
            .zsync_runtime = zsync_runtime_ptr,
            .async_bridge = async_bridge,
            .events = events.Queue.init(),
            .wayland_watch_fd = null,
            .pending_wayland_dispatch = false,
            .failure = null,
        };

        try runtime.installWaylandWatch();

        return runtime;
    }

    pub fn deinit(self: *Runtime) void {
        self.teardownWaylandWatch();
        self.client.deinit();
        self.async_bridge.deinit();
        self.zsync_runtime = null;
        self.events.deinit(self.allocator);
        self.event_loop.deinit();
    }

    pub fn destroy(self: *Runtime) void {
        const allocator = self.allocator;
        self.deinit();
        allocator.destroy(self);
    }

    /// Pump pending zigzag events and drive the Wayland client.
    pub fn pump(self: *Runtime) !void {
        if (self.failure) |err| return err;

        _ = try self.event_loop.tick();

        if (self.failure) |err| return err;

        try self.drainWayland();
    }

    pub fn hasAsync(self: *const Runtime) bool {
        return self.async_bridge.isEnabled();
    }

    pub fn runAsyncTask(self: *Runtime, comptime task_fn: anytype, args: anytype) !void {
        return self.async_bridge.runTask(task_fn, args);
    }

    pub fn pollEvent(self: *Runtime) ?events.Event {
        return self.events.pop();
    }

    fn pushEvent(self: *Runtime, event: events.Event) Error!void {
        try self.events.push(self.allocator, event);
    }

    fn installWaylandWatch(self: *Runtime) !void {
        const fd = try self.getWaylandFd();
        const watch = try self.event_loop.addFd(fd, .{ .read = true, .hangup = true, .io_error = true });
        self.event_loop.setCallback(watch, watchCallback);

        if (self.event_loop.watches.getPtr(fd)) |stored_watch| {
            stored_watch.user_data = @as(?*anyopaque, @ptrCast(self));
        }

        self.wayland_watch_fd = fd;
    }

    fn teardownWaylandWatch(self: *Runtime) void {
        if (self.wayland_watch_fd) |fd| {
            if (self.event_loop.watches.getPtr(fd)) |watch_ptr| {
                self.event_loop.removeFd(watch_ptr);
            }
            self.wayland_watch_fd = null;
        }
    }

    fn getWaylandFd(self: *Runtime) !i32 {
        const handle = self.client.connection.socket.handle;
        return @as(i32, handle);
    }

    fn handleWaylandWatch(self: *Runtime, watch: *const zigzag.Watch, event: zigzag.Event) void {
        switch (event.type) {
            .read_ready => {
                self.pending_wayland_dispatch = true;
            },
            .hangup => {
                std.log.err("Wayland connection hangup signaled", .{});
                self.failure = Error.WaylandHangup;
                self.event_loop.removeFd(watch);
                self.pushEvent(.{ .kind = .wayland_hangup }) catch |err| {
                    std.log.err("Failed to queue hangup event: {}", .{err});
                };
            },
            .io_error => {
                std.log.err("Wayland watcher reported I/O error", .{});
                self.failure = Error.WaylandDispatchFailed;
                self.event_loop.removeFd(watch);
                self.pushEvent(.{ .kind = .wayland_io_error }) catch |err| {
                    std.log.err("Failed to queue io_error event: {}", .{err});
                };
            },
            else => {},
        }
    }

    fn drainWayland(self: *Runtime) Error!void {
        if (!self.pending_wayland_dispatch) return;

        self.pending_wayland_dispatch = false;

        self.client.dispatch() catch |err| {
            switch (err) {
                error.ConnectionClosed => {
                    self.failure = Error.WaylandConnectionClosed;
                    self.pushEvent(.{ .kind = .wayland_connection_closed }) catch |push_err| {
                        std.log.err("Failed to queue connection_closed event: {}", .{push_err});
                    };
                    return Error.WaylandConnectionClosed;
                },
                else => {
                    std.log.err("Wayland dispatch failed: {}", .{err});
                    self.failure = Error.WaylandDispatchFailed;
                    self.pushEvent(.{ .kind = .wayland_io_error }) catch |push_err| {
                        std.log.err("Failed to queue dispatch failure event: {}", .{push_err});
                    };
                    return Error.WaylandDispatchFailed;
                },
            }
        };

        try self.pushEvent(.{ .kind = .wayland_dispatch });
    }

    fn watchCallback(watch: *const zigzag.Watch, event: zigzag.Event) void {
        const context = watch.user_data orelse return;
        std.debug.assert(@intFromPtr(context) % @alignOf(Runtime) == 0);
        const runtime = @as(*Runtime, @ptrCast(context));
        runtime.handleWaylandWatch(watch, event);
    }
};
