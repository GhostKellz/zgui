# 🐆 Jaguar — The Modern Zig GUI & WASM Toolkit

[![Built with Zig](https://img.shields.io/badge/Built%20with%20Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/⚡%200.16.0--dev-FF7043?style=for-the-badge)](https://ziglang.org/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-654FF0?style=for-the-badge&logo=webassembly&logoColor=white)]()
[![Desktop GUI](https://img.shields.io/badge/Desktop%20GUI-2E3440?style=for-the-badge&logo=gnome&logoColor=white)]()
[![Wayland Native](https://img.shields.io/badge/Wayland%20Native-FFC432?style=for-the-badge&logo=wayland&logoColor=black)]()

---

**Jaguar** is a blazing-fast, async-native GUI framework and WASM toolkit for Zig v0.15+. Effortless for native desktop apps and next-gen web apps. Inspired by egui, Iced, and Tauri, but rebuilt from scratch for Zig’s async/await, GPU-accelerated rendering, and live hot-reload dev experience.

---

## ✨ Features

* 🐆 **Pure Zig:** Native types, zero C glue, built for performance
* 🌍 **Desktop + Web:** Compile for desktop or browser (WASM) from a single codebase
* ⚡ **Async-first:** Powered by [zsync](https://github.com/ghostkellz/zsync) for smooth, non-blocking UI and background tasks
* 🎨 **Theming:** Live theming, dark/light mode, CSS-like styling
* 🧩 **Composable Widgets:** Buttons, lists, tabs, tables, graphs, forms, dialogs, trees, markdown, icons, SVG, more
* 🖥️ **Windowing:** Multi-window, dialogs, notifications, overlays
* 🚀 **GPU Accel:** OpenGL/WebGPU rendering, with CPU fallback
* 📦 **Hot reload:** Live update your UI as you code
* 🕹️ **Full Input:** Mouse, keyboard, touch, focus, clipboard
* 🖼️ **Layout Engine:** Flex, grid, stack, float, absolute
* 🧬 **Reactive State:** Signal/observable patterns for instant UI updates
* 🧪 **Testing:** Snapshot & integration test support

---

## 📦 Quick Start

**Requirements:**

* Zig v0.15+
* For WASM: wasm-pack, simple HTTP server, or static site host

```sh
git clone https://github.com/ghostkellz/jaguar.git
cd jaguar

# Desktop demo
zig build run

# Examples
zig build examples

# WASM build
zig build wasm

# Serve WASM demo
python3 serve_demo.py
# Then open http://localhost:8000/demo.html
```

Or add to your build.zig:

```zig
const jaguar_dep = b.dependency("jaguar", .{ .target = target, .optimize = optimize });
const jaguar = jaguar_dep.module("jaguar");
```

---

## 🖥️ Example Usage (Desktop)

```zig
const jaguar = @import("jaguar");

pub fn main() !void {
    var app = try jaguar.App.init(.{ .title = "Jaguar Demo" });
    defer app.deinit();

    app.window(.{ .title = "Dashboard", .width = 800, .height = 600 }) |win| {
        win.column(|col| {
            col.text("Welcome to Jaguar! 🚀");
            col.button("Click me", .{ .onClick = on_button_click });
            col.graph({ .points = &[_]f32{ 1.0, 2.0, 1.5, 3.2 } });
        });
    };

    try app.run();
}

fn on_button_click(ctx: *jaguar.Context) void {
    ctx.notify("Button pressed!");
}
```

---

## 🌐 Example Usage (Browser/WASM)

```zig
const jaguar = @import("jaguar");

export fn main() void {
    jaguar.web.start(.{
        .title = "Jaguar Web Demo",
        .root = |ui| {
            ui.row(|row| {
                row.text("Hello from WASM!");
                row.button("Reload", .{ .onClick = reload_page });
            });
        }
    });
}

fn reload_page(ctx: *jaguar.Context) void {
    ctx.reload();
}
```

---

## � Current Status

**Jaguar v0.1.0-alpha** - Core foundation is complete!

✅ **Completed:**
- Pure Zig project structure with Zig 0.15+ compatibility
- Cross-platform abstraction layer (Desktop/WASM)
- Immediate mode UI widget system (text, button, input, slider, checkbox)
- Event handling framework (mouse, keyboard, window events)
- Theming system with light/dark modes
- WASM build pipeline with JavaScript interop
- Working examples and demo applications

🚧 **In Progress:**
- Windowing system integration (GLFW, SDL)
- GPU-accelerated rendering (OpenGL, WebGL)
- Advanced layout engine (flex, grid, constraints)
- zsync async runtime integration

🔜 **Coming Next:**
- Hot reload development experience
- Advanced widgets (tables, trees, graphs)
- File system access and native dialogs
- Performance optimization and benchmarks

---

## �🗺️ Roadmap

* [x] Async event loop + zsync integration
* [x] Core widget set (button, list, text, input, progress)
* [x] Desktop app: windowing, dialogs, overlays
* [x] WASM: browser build, DOM integration, events
* [ ] Full theming & style system
* [ ] Advanced layout engine (flex, grid, stack)
* [ ] GPU-accelerated rendering (OpenGL/WebGPU)
* [ ] Advanced widgets (table, tree, charts, markdown)
* [ ] Signal-based reactive state
* [ ] Hot reload for dev
* [ ] Plugins: file picker, notifications, menus
* [ ] Drag & drop, clipboard
* [ ] Animation, transitions
* [ ] Native + web file system access
* [ ] Accessibility support (a11y)
* [ ] Comprehensive documentation
* [ ] WASM performance benchmarks

---

## 🤝 Contributing

PRs, issues, widget ideas, and flames welcome!
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines and style.

---

## 🐆 Built for the future of Zig GUIs by [GhostKellz](https://github.com/ghostkellz)

