const std = @import("std");
const Io = std.Io;

pub const zfont = @import("zfont");

pub const FontHandle = struct {
    index: usize,
};

const FontEntry = struct {
    name: []u8,
    path: []u8,
    data: []u8,
    font: *zfont.Font,
};

const default_font_name = "default";
const default_font_env_var = "ZGUI_FONT_PATH";
const max_font_bytes: usize = 32 * 1024 * 1024;

/// FontManager owns font resources and exposes handles for layout and rendering.
/// Requires an Io instance for file operations.
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    io: Io,
    entries: std.ArrayList(FontEntry) = .{},
    default_font: ?FontHandle = null,
    renderer: ?zfont.GlyphRenderer = null,

    pub const LoadError = error{
        FontParseFailed,
        StreamTooLong,
    } || std.mem.Allocator.Error || Io.File.OpenError || Io.File.Reader.Error || Io.Reader.LimitedAllocError;

    pub const GlyphError = LoadError || zfont.FontError || error{UnknownFontHandle};

    pub const GlyphImage = struct {
        pixels: []const u8,
        width: u32,
        height: u32,
        bearing_x: i32,
        bearing_y: i32,
        advance_x: f32,
        advance_y: f32,
    };

    pub fn init(allocator: std.mem.Allocator, io: Io) FontManager {
        return .{
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn deinit(self: *FontManager) void {
        for (self.entries.items) |entry| {
            entry.font.deinit();
            self.allocator.destroy(entry.font);
            self.allocator.free(entry.name);
            self.allocator.free(entry.path);
            self.allocator.free(entry.data);
        }
        self.entries.deinit(self.allocator);
        self.default_font = null;
        if (self.renderer) |*renderer| {
            renderer.deinit();
        }
        self.renderer = null;
    }

    pub fn loadFont(self: *FontManager, name: []const u8, path: []const u8) LoadError!FontHandle {
        if (self.findByName(name)) |handle| return handle;

        const file = try openFile(self.io, path);
        defer file.close(self.io);

        var read_buffer: [4096]u8 = undefined;
        var file_reader = file.reader(self.io, &read_buffer);
        var data_owned = true;
        const data = try file_reader.interface.allocRemaining(self.allocator, Io.Limit.limited(max_font_bytes));
        errdefer if (data_owned) self.allocator.free(data);

        const font_instance = zfont.Font.init(self.allocator, data) catch |font_err| {
            if (font_err == error.OutOfMemory) return error.OutOfMemory;
            return error.FontParseFailed;
        };

        const font = try self.allocator.create(zfont.Font);
        var font_owned = true;
        errdefer if (font_owned) {
            font.deinit();
            self.allocator.destroy(font);
        };
        font.* = font_instance;

        const name_copy = try self.allocator.dupe(u8, name);
        var name_owned = true;
        errdefer if (name_owned) self.allocator.free(name_copy);

        const path_copy = try self.allocator.dupe(u8, path);
        var path_owned = true;
        errdefer if (path_owned) self.allocator.free(path_copy);

        const handle = FontHandle{ .index = self.entries.items.len };
        try self.entries.append(self.allocator, FontEntry{
            .name = name_copy,
            .path = path_copy,
            .data = data,
            .font = font,
        });

        name_owned = false;
        path_owned = false;
        data_owned = false;
        font_owned = false;

        if (std.mem.eql(u8, name, default_font_name)) {
            self.default_font = handle;
        }

        return handle;
    }

    pub fn loadDefault(self: *FontManager) (LoadError || error{NoUsableFont})!FontHandle {
        if (self.default_font) |handle| return handle;

        if (self.findByName(default_font_name)) |cached| {
            self.default_font = cached;
            return cached;
        }

        // Check environment variable for custom font path (requires libc)
        if (comptime @import("builtin").link_libc) {
            if (std.c.getenv(default_font_env_var)) |env_ptr| {
                const env_path = std.mem.span(env_ptr);
                if (self.tryLoadDefault(env_path)) |handle| return handle;
            }
        }

        const candidates = [_][]const u8{
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSansNarrow-Regular.ttf",
            "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
            "/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/SFNS.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf",
        };

        for (candidates) |candidate| {
            if (try self.tryLoadDefault(candidate)) |handle| return handle;
        }

        return error.NoUsableFont;
    }

    pub fn get(self: *FontManager, handle: FontHandle) ?*zfont.Font {
        if (handle.index >= self.entries.items.len) return null;
        return self.entries.items[handle.index].font;
    }

    pub fn defaultHandle(self: *const FontManager) ?FontHandle {
        return self.default_font;
    }

    pub fn findByName(self: *const FontManager, name: []const u8) ?FontHandle {
        for (self.entries.items, 0..) |entry, idx| {
            if (std.mem.eql(u8, entry.name, name)) {
                return FontHandle{ .index = idx };
            }
        }
        return null;
    }

    fn tryLoadDefault(self: *FontManager, path: []const u8) LoadError!?FontHandle {
        const handle = self.loadFont(default_font_name, path) catch |err| switch (err) {
            error.FileNotFound,
            error.NotDir,
            error.AccessDenied,
            error.IsDir,
            error.PermissionDenied => {
                return null;
            },
            error.FontParseFailed => {
                std.log.warn("failed to parse font candidate '{s}'", .{path});
                return null;
            },
            else => return err,
        };
        self.default_font = handle;
        return handle;
    }

    pub fn getGlyphImage(
        self: *FontManager,
        handle: FontHandle,
        codepoint: u32,
        options: zfont.RenderOptions,
    ) GlyphError!GlyphImage {
        const font = self.get(handle) orelse return error.UnknownFontHandle;
        var renderer = self.ensureRenderer();
        const rendered = try renderer.renderGlyph(font, codepoint, options);

        return GlyphImage{
            .pixels = rendered.bitmap,
            .width = rendered.width,
            .height = rendered.height,
            .bearing_x = rendered.bearing_x,
            .bearing_y = rendered.bearing_y,
            .advance_x = @as(f32, @floatFromInt(rendered.advance_x)),
            .advance_y = @as(f32, @floatFromInt(rendered.advance_y)),
        };
    }

    pub fn getGlyphImageDefault(
        self: *FontManager,
        codepoint: u32,
        size: f32,
    ) GlyphError!GlyphImage {
        const handle = try self.loadDefault();
    const options = zfont.RenderOptions{ .size = size };
    return self.getGlyphImage(handle, codepoint, options);
    }

    fn ensureRenderer(self: *FontManager) *zfont.GlyphRenderer {
        if (self.renderer) |*renderer| return renderer;
        self.renderer = zfont.GlyphRenderer.init(self.allocator);
        return &self.renderer.?;
    }
};

fn openFile(io: Io, path: []const u8) Io.File.OpenError!Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return Io.Dir.openFileAbsolute(io, path, .{});
    }
    return Io.Dir.cwd().openFile(io, path, .{});
}

test "FontManager ensureRenderer caches instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var manager = FontManager.init(allocator, std.testing.io);
    defer manager.deinit();

    const renderer_a = manager.ensureRenderer();
    try std.testing.expect(renderer_a == &manager.renderer.?);

    const renderer_b = manager.ensureRenderer();
    try std.testing.expect(renderer_a == renderer_b);
}

test "FontManager getGlyphImage invalid handle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var manager = FontManager.init(allocator, std.testing.io);
    defer manager.deinit();

    const handle = FontHandle{ .index = 42 };
    try std.testing.expectError(error.UnknownFontHandle, manager.getGlyphImage(handle, 'A', zfont.RenderOptions{ .size = 16.0 }));
}
