const std = @import("std");

pub const EventKind = enum {
    /// Fired after a Wayland dispatch cycle completes successfully.
    wayland_dispatch,
    /// Fired when the compositor signals the connection is closing.
    wayland_connection_closed,
    /// Fired when the Wayland FD reports an unrecoverable I/O error.
    wayland_io_error,
    /// Fired when the Wayland socket hang ups without a clean close.
    wayland_hangup,
};

pub const Event = struct {
    kind: EventKind,
};

pub const Queue = struct {
    buffer: std.ArrayListUnmanaged(Event) = .{},

    pub fn init() Queue {
        return Queue{};
    }

    pub fn deinit(self: *Queue, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }

    pub fn push(self: *Queue, allocator: std.mem.Allocator, event: Event) !void {
        try self.buffer.append(allocator, event);
    }

    pub fn pop(self: *Queue) ?Event {
        if (self.buffer.items.len == 0) return null;
        const event = self.buffer.items[0];
        _ = self.buffer.orderedRemove(0);
        return event;
    }

    pub fn clear(self: *Queue) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn len(self: *const Queue) usize {
        return self.buffer.items.len;
    }
};
