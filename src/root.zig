//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Io = std.Io;

pub const runtime = @import("runtime/loop.zig");

pub const text = struct {
    pub const fonts = @import("text/fonts.zig");
    pub const layout = @import("text/layout.zig");
};

/// Demonstrates buffered stdout writing using the Io abstraction.
/// Requires an Io instance to perform the write operation.
pub fn bufferedPrint(io: Io) !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test "FontManager initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var manager = text.fonts.FontManager.init(arena.allocator(), std.testing.io);
    defer manager.deinit();
    try std.testing.expect(manager.defaultHandle() == null);
}

test "TextLayout initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var manager = text.fonts.FontManager.init(arena.allocator(), std.testing.io);
    defer manager.deinit();
    const layout = text.layout.TextLayout.init(arena.allocator(), &manager);
    _ = layout;
}
