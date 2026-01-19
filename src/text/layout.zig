const std = @import("std");

const gcode = @import("gcode");
const fonts = @import("fonts.zig");

const replacement_codepoint: u32 = 0xfffd; // Unicode replacement character

const Cluster = struct {
    bytes: []const u8,
    cp_start: usize,
    cp_len: usize,
};

const FontSelection = struct {
    font: *fonts.zfont.Font,
    handle: fonts.FontHandle,
};

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn len(self: Span) usize {
        return self.end - self.start;
    }
};

pub const GlyphPlacement = struct {
    codepoint: u32,
    font: fonts.FontHandle,
    advance: f32,
    x: f32,
    line: usize,
};

pub const LineMetrics = struct {
    index: usize,
    width: f32,
    ascent: f32,
    descent: f32,
    height: f32,
    baseline: f32,
    glyph_range: Span,
    text_range: Span,
    direction: gcode.Direction,
};

pub const LayoutMetrics = struct {
    width: f32,
    height: f32,
    ascent: f32,
    descent: f32,
    line_count: usize,
};

const LineShape = struct {
    width: f32,
    ascent: f32,
    descent: f32,
    height: f32,
    direction: gcode.Direction,
};

pub const ShapeOptions = struct {
    font: ?fonts.FontHandle = null,
    size: f32 = 16.0,
    fallback_codepoint: u32 = '?',
    direction: ?gcode.Direction = null,
    fallback_fonts: []const fonts.FontHandle = &.{},
    script_fallbacks: []const ScriptFallback = &.{},

    pub const ScriptFallback = struct {
        script: gcode.Script,
        font: fonts.FontHandle,
    };
};

pub const ShapeResult = struct {
    glyphs: std.ArrayList(GlyphPlacement),
    lines: std.ArrayList(LineMetrics),
    metrics: LayoutMetrics,

    pub fn deinit(self: *ShapeResult, allocator: std.mem.Allocator) void {
        self.glyphs.deinit(allocator);
        self.lines.deinit(allocator);
    }
};

/// TextLayout consumes glyph metrics to produce positioned runs.
pub const TextLayout = struct {
    allocator: std.mem.Allocator,
    font_manager: *fonts.FontManager,

    pub const ShapeError = error{
        InvalidUtf8,
        InvalidFontSize,
        UnknownFontHandle,
    } || fonts.FontManager.LoadError || error{NoUsableFont} || fonts.zfont.FontError;

    pub fn init(allocator: std.mem.Allocator, font_manager: *fonts.FontManager) TextLayout {
        return .{
            .allocator = allocator,
            .font_manager = font_manager,
        };
    }

    pub fn shape(self: *TextLayout, text: []const u8, options: ShapeOptions) ShapeError!ShapeResult {
        if (options.size <= 0) return error.InvalidFontSize;

        const base_handle = blk: {
            if (options.font) |handle| break :blk handle;
            if (self.font_manager.defaultHandle()) |handle| break :blk handle;
            break :blk try self.font_manager.loadDefault();
        };

        const base_font = self.font_manager.get(base_handle) orelse return error.UnknownFontHandle;

        var glyphs: std.ArrayList(GlyphPlacement) = .empty;
        errdefer glyphs.deinit(self.allocator);

        var lines: std.ArrayList(LineMetrics) = .empty;
        errdefer lines.deinit(self.allocator);

        _ = std.unicode.Utf8View.init(text) catch return error.InvalidUtf8;

        if (text.len == 0) {
            const ascent = base_font.getAscent(options.size);
            const descent = base_font.getDescent(options.size);
            const line_height = base_font.getLineHeight(options.size);
            try lines.append(self.allocator, LineMetrics{
                .index = 0,
                .width = 0,
                .ascent = ascent,
                .descent = descent,
                .height = line_height,
                .baseline = ascent,
                .glyph_range = Span{ .start = 0, .end = 0 },
                .text_range = Span{ .start = 0, .end = 0 },
                .direction = options.direction orelse gcode.Direction.LTR,
            });

            return ShapeResult{
                .glyphs = glyphs,
                .lines = lines,
                .metrics = LayoutMetrics{
                    .width = 0,
                    .height = line_height,
                    .ascent = ascent,
                    .descent = descent,
                    .line_count = 1,
                },
            };
        }

        var offset: usize = 0;
        var overall_width: f32 = 0;
        var overall_ascent = base_font.getAscent(options.size);
        var overall_descent = base_font.getDescent(options.size);
        var total_height: f32 = 0;
        var line_count: usize = 0;

        while (offset <= text.len) {
            const remainder = text[offset..];
            const newline_pos = std.mem.indexOfScalar(u8, remainder, '\n');
            const line_end = if (newline_pos) |rel| offset + rel else text.len;
            const line_slice = text[offset..line_end];

            const glyph_start = glyphs.items.len;
            const line_index = line_count;

            const line_shape = try self.shapeLine(
                line_slice,
                options,
                base_handle,
                &glyphs,
                line_index,
            );

            const glyph_end = glyphs.items.len;

            if (line_shape.width > overall_width) overall_width = line_shape.width;
            if (line_shape.ascent > overall_ascent) overall_ascent = line_shape.ascent;
            if (line_shape.descent > overall_descent) overall_descent = line_shape.descent;
            total_height += line_shape.height;

            try lines.append(self.allocator, LineMetrics{
                .index = line_index,
                .width = line_shape.width,
                .ascent = line_shape.ascent,
                .descent = line_shape.descent,
                .height = line_shape.height,
                .baseline = line_shape.ascent,
                .glyph_range = Span{ .start = glyph_start, .end = glyph_end },
                .text_range = Span{ .start = offset, .end = line_end },
                .direction = line_shape.direction,
            });

            line_count += 1;

            if (newline_pos) |_| {
                offset = line_end + 1;
                if (offset > text.len) break;
            } else {
                break;
            }
        }

        const metrics = LayoutMetrics{
            .width = overall_width,
            .height = total_height,
            .ascent = overall_ascent,
            .descent = overall_descent,
            .line_count = line_count,
        };

        return ShapeResult{
            .glyphs = glyphs,
            .lines = lines,
            .metrics = metrics,
        };
    }

    fn shapeLine(
        self: *TextLayout,
        line: []const u8,
        options: ShapeOptions,
        base_handle: fonts.FontHandle,
        glyphs: *std.ArrayList(GlyphPlacement),
        line_index: usize,
    ) ShapeError!LineShape {
        const base_font = self.font_manager.get(base_handle) orelse unreachable;

        if (line.len == 0) {
            return LineShape{
                .width = 0,
                .ascent = base_font.getAscent(options.size),
                .descent = base_font.getDescent(options.size),
                .height = base_font.getLineHeight(options.size),
                .direction = options.direction orelse gcode.Direction.LTR,
            };
        }

        var clusters: std.ArrayList(Cluster) = .empty;
        defer clusters.deinit(self.allocator);

        var codepoints: std.ArrayList(u32) = .empty;
        defer codepoints.deinit(self.allocator);

        var grapheme_iter = gcode.GraphemeIterator.init(line);
        while (grapheme_iter.next()) |cluster_bytes| {
            if (cluster_bytes.len == 0) continue;
            if (cluster_bytes.len == 1 and cluster_bytes[0] == '\r') continue;

            const cp_start = codepoints.items.len;
            var cp_iter = gcode.codePointIterator(cluster_bytes);
            while (cp_iter.next()) |info| {
                try codepoints.append(self.allocator, @intCast(info.code));
            }

            const cp_len = codepoints.items.len - cp_start;
            try clusters.append(self.allocator, .{
                .bytes = cluster_bytes,
                .cp_start = cp_start,
                .cp_len = cp_len,
            });
        }

        if (clusters.items.len == 0) {
            return LineShape{
                .width = 0,
                .ascent = base_font.getAscent(options.size),
                .descent = base_font.getDescent(options.size),
                .height = base_font.getLineHeight(options.size),
                .direction = options.direction orelse gcode.Direction.LTR,
            };
        }

        const cp_len_total = codepoints.items.len;
        var cp_scripts = try self.allocator.alloc(gcode.Script, cp_len_total);
        defer self.allocator.free(cp_scripts);

        if (cp_len_total > 0) {
            @memset(cp_scripts, gcode.Script.Common);
            var script_detector = gcode.ScriptDetector.init(self.allocator);
            const script_runs = try script_detector.detectRuns(codepoints.items);
            defer self.allocator.free(script_runs);

            for (script_runs) |run| {
                for (run.start..run.end()) |idx| {
                    cp_scripts[idx] = run.script;
                }
            }
        }

        var cp_to_cluster = try self.allocator.alloc(usize, cp_len_total);
        defer self.allocator.free(cp_to_cluster);

        for (clusters.items, 0..) |cluster, idx| {
            for (cluster.cp_start..cluster.cp_start + cluster.cp_len) |cp_index| {
                cp_to_cluster[cp_index] = idx;
            }
        }

        var bidi_engine = gcode.BiDi.init(self.allocator);
        const base_dir = options.direction orelse blk: {
            if (cp_len_total == 0) break :blk gcode.Direction.LTR;
            break :blk bidi_engine.getBaseDirection(codepoints.items);
        };

        const runs = if (cp_len_total == 0)
            try self.allocator.dupe(gcode.Run, &[_]gcode.Run{})
        else
            try bidi_engine.processText(codepoints.items, base_dir);
        defer self.allocator.free(runs);

        var cluster_order: std.ArrayList(usize) = .empty;
        defer cluster_order.deinit(self.allocator);

        for (runs) |run| {
            var run_clusters: std.ArrayList(usize) = .empty;
            defer run_clusters.deinit(self.allocator);

            var prev_cluster: ?usize = null;
            for (run.start..run.end()) |cp_index| {
                const cluster_idx = cp_to_cluster[cp_index];
                if (prev_cluster == null or prev_cluster.? != cluster_idx) {
                    try run_clusters.append(self.allocator, cluster_idx);
                    prev_cluster = cluster_idx;
                }
            }

            if (run.isRTL()) {
                var i = run_clusters.items.len;
                while (i > 0) {
                    i -= 1;
                    const idx = run_clusters.items[i];
                    if (cluster_order.items.len == 0 or cluster_order.items[cluster_order.items.len - 1] != idx) {
                        try cluster_order.append(self.allocator, idx);
                    }
                }
            } else {
                for (run_clusters.items) |idx| {
                    if (cluster_order.items.len == 0 or cluster_order.items[cluster_order.items.len - 1] != idx) {
                        try cluster_order.append(self.allocator, idx);
                    }
                }
            }
        }

        if (cluster_order.items.len == 0) {
            for (clusters.items, 0..) |_, idx| {
                try cluster_order.append(self.allocator, idx);
            }
        }

        var cursor_x: f32 = 0;
        var line_ascent = base_font.getAscent(options.size);
        var line_descent = base_font.getDescent(options.size);
        var line_height = base_font.getLineHeight(options.size);
        var previous_state: ?struct {
            handle: fonts.FontHandle,
            codepoint: u32,
        } = null;

        for (cluster_order.items) |cluster_idx| {
            const cluster = clusters.items[cluster_idx];
            if (cluster.cp_len == 0) continue;

            const cp_slice = codepoints.items[cluster.cp_start .. cluster.cp_start + cluster.cp_len];
            const script = cp_scripts[cluster.cp_start];

            const selection = self.selectFontForCluster(
                cp_slice,
                script,
                base_handle,
                options,
            );

            const font = selection.font;
            const handle = selection.handle;

            const ascent = font.getAscent(options.size);
            const descent = font.getDescent(options.size);
            const lh = font.getLineHeight(options.size);
            if (ascent > line_ascent) line_ascent = ascent;
            if (descent > line_descent) line_descent = descent;
            if (lh > line_height) line_height = lh;

            for (cp_slice) |cp| {
                var codepoint = cp;

                if (!font.hasGlyph(codepoint)) {
                    if (options.fallback_codepoint != codepoint and font.hasGlyph(options.fallback_codepoint)) {
                        codepoint = options.fallback_codepoint;
                    } else if (font.hasGlyph(replacement_codepoint)) {
                        codepoint = replacement_codepoint;
                    } else {
                        continue;
                    }
                }

                if (previous_state) |prev| {
                    if (prev.handle.index == handle.index) {
                        cursor_x += font.getKerning(prev.codepoint, codepoint, options.size);
                        if (cursor_x < 0) cursor_x = 0;
                    }
                }

                const advance = font.getAdvanceWidth(codepoint, options.size) catch |err| switch (err) {
                    error.GlyphNotFound => continue,
                    else => return err,
                };

                try glyphs.append(self.allocator, .{
                    .codepoint = codepoint,
                    .font = handle,
                    .advance = advance,
                    .x = cursor_x,
                    .line = line_index,
                });

                cursor_x += advance;
                previous_state = .{ .handle = handle, .codepoint = codepoint };
            }
        }

        return LineShape{
            .width = cursor_x,
            .ascent = line_ascent,
            .descent = line_descent,
            .height = line_height,
            .direction = base_dir,
        };
    }

    fn selectFontForCluster(
        self: *TextLayout,
        codepoints: []const u32,
        script: gcode.Script,
        base_handle: fonts.FontHandle,
        options: ShapeOptions,
    ) FontSelection {
        const base_font = self.font_manager.get(base_handle) orelse unreachable;
        if (clusterSupported(base_font, codepoints, script)) {
            return .{ .font = base_font, .handle = base_handle };
        }

        for (options.script_fallbacks) |fallback| {
            if (fallback.script != script) continue;
            if (self.font_manager.get(fallback.font)) |font| {
                if (clusterSupported(font, codepoints, script)) {
                    return .{ .font = font, .handle = fallback.font };
                }
            }
        }

        for (options.fallback_fonts) |handle| {
            if (self.font_manager.get(handle)) |font| {
                if (clusterSupported(font, codepoints, script)) {
                    return .{ .font = font, .handle = handle };
                }
            }
        }

        return .{ .font = base_font, .handle = base_handle };
    }
};

fn clusterSupported(font: *fonts.zfont.Font, codepoints: []const u32, script: gcode.Script) bool {
    // Note: Script-based font selection is disabled until zfont exports Script enum
    // from its root module. For now, we only check glyph coverage.
    _ = script;

    for (codepoints) |cp| {
        if (!font.hasGlyph(cp)) return false;
    }

    return true;
}

test "Span len computes difference" {
    const span = Span{ .start = 2, .end = 7 };
    try std.testing.expectEqual(@as(usize, 5), span.len());
}

test "TextLayout errors when default font missing entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var manager = fonts.FontManager.init(allocator, std.testing.io);
    defer manager.deinit();
    manager.default_font = fonts.FontHandle{ .index = 0 };

    var layout = TextLayout.init(allocator, &manager);
    try std.testing.expectError(error.UnknownFontHandle, layout.shape("hi", ShapeOptions{}));
}
