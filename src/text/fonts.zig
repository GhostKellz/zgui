const std = @import("std");

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
pub const FontManager = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(FontEntry),
    default_font: ?FontHandle = null,
    renderer: ?zfont.GlyphRenderer = null,

    pub const LoadError = error{
        FontParseFailed,
    } || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

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

    pub fn init(allocator: std.mem.Allocator) FontManager {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(FontEntry).init(allocator),
            .default_font = null,
            .renderer = null,
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
        self.entries.deinit();
        self.default_font = null;
        if (self.renderer) |*renderer| {
            renderer.deinit();
        }
        self.renderer = null;
    }

    pub fn loadFont(self: *FontManager, name: []const u8, path: []const u8) LoadError!FontHandle {
        if (self.findByName(name)) |handle| return handle;

        const file = try openFile(path);
        defer file.close();

        var data_owned = true;
        const data = try file.readToEndAlloc(self.allocator, max_font_bytes);
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
        try self.entries.append(FontEntry{
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

        if (std.posix.getenv(default_font_env_var)) |env_ptr| {
            const env_path = std.mem.span(env_ptr);
            if (self.tryLoadDefault(env_path)) |handle| return handle;
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
            if (self.tryLoadDefault(candidate)) |handle| return handle;
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

fn openFile(path: []const u8) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return std.fs.openFileAbsolute(path, .{});
    }
    return std.fs.cwd().openFile(path, .{});
}

test "FontManager ensureRenderer caches instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var manager = FontManager.init(allocator);
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

    var manager = FontManager.init(allocator);
    defer manager.deinit();

    const handle = FontHandle{ .index = 42 };
    try std.testing.expectError(error.UnknownFontHandle, manager.getGlyphImage(handle, 'A', zfont.RenderOptions{ .size = 16.0 }));
}
