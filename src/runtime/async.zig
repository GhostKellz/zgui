const std = @import("std");
const zsync = @import("zsync");

/// Thin wrapper that exposes scheduling hooks into an optional zsync runtime.
pub const AsyncBridge = struct {
    allocator: std.mem.Allocator,
    runtime: ?*zsync.runtime.Runtime,
    owns_runtime: bool,

    pub const Error = error{ ZsyncUnavailable };

    pub fn disabled(allocator: std.mem.Allocator) AsyncBridge {
        return AsyncBridge{
            .allocator = allocator,
            .runtime = null,
            .owns_runtime = false,
        };
    }

    pub fn init(
        allocator: std.mem.Allocator,
        runtime: ?*zsync.runtime.Runtime,
        owns_runtime: bool,
    ) AsyncBridge {
        return AsyncBridge{
            .allocator = allocator,
            .runtime = runtime,
            .owns_runtime = owns_runtime,
        };
    }

    pub fn deinit(self: *AsyncBridge) void {
        if (self.owns_runtime) {
            if (self.runtime) |rt| {
                rt.deinit();
            }
        }
        self.runtime = null;
        self.owns_runtime = false;
    }

    pub fn isEnabled(self: *const AsyncBridge) bool {
        return self.runtime != null;
    }

    pub fn getRuntime(self: *const AsyncBridge) ?*zsync.runtime.Runtime {
        return self.runtime;
    }

    pub fn runTask(self: *AsyncBridge, comptime task_fn: anytype, args: anytype) !void {
        if (self.runtime) |rt| {
            try rt.run(task_fn, args);
        } else {
            return Error.ZsyncUnavailable;
        }
    }
};
