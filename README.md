![zgui Jaguar Mascot](assets/icons/zgui-primary.png)

# 🐆 zgui — The Agile Zig GUI Framework

[![Built with Zig](https://img.shields.io/badge/Built%20with%20Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=yellow)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/⚡%200.16.0--dev-FF7043?style=for-the-badge)](https://ziglang.org/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-654FF0?style=for-the-badge&logo=webassembly&logoColor=white)]()
[![Desktop GUI](https://img.shields.io/badge/Desktop%20GUI-2E3440?style=for-the-badge&logo=gnome&logoColor=white)]()
[![Wayland Native](https://img.shields.io/badge/Wayland%20Native-FFC432?style=for-the-badge&logo=wayland&logoColor=black)]()

---

**zgui** harnesses the power and agility of the jaguar - nature's most adaptable big cat. Like its mascot, zgui strikes with precision, adapts to any environment (desktop or web), and moves with unmatched performance. Built purely in Zig for developers who demand speed, flexibility, and elegance in their GUI applications.

---

## ✨ Why zgui? The Jaguar Advantage

* 🐆 **Agile & Fast:** Like a jaguar, zgui pounces on performance bottlenecks with pure Zig efficiency
* 🌍 **Adaptive:** Seamlessly prowls across desktop and web environments from a single codebase
* ⚡ **Lightning Reflexes:** Async-first architecture for responsive, non-blocking UI interactions
* 🎨 **Sleek Design:** Beautiful theming system with dark/light modes and customizable styles
* 🧩 **Powerful Components:** Rich widget ecosystem for building sophisticated interfaces
* 🖥️ **Territory Control:** Multi-window support with dialogs, notifications, and overlays
* 🚀 **GPU Accelerated:** Harnesses raw GPU power for silky-smooth rendering
* 📦 **Live Evolution:** Hot reload keeps you in the flow while developing
* 🕹️ **Total Awareness:** Complete input handling for mouse, keyboard, touch, and clipboard
* 🖼️ **Flexible Hunting Grounds:** Advanced layout engine with flex, grid, and absolute positioning
* 🧬 **Reactive Instincts:** Signal-based state management for instant UI updates
* 🧪 **Battle-tested:** Comprehensive testing framework for reliable applications

---

## 📦 Quick Start

**Requirements:**

* Zig v0.15+
* For WASM: wasm-pack, simple HTTP server, or static site host

```sh
git clone https://github.com/ghostkellz/zgui.git
cd zgui

# Desktop demo - watch the jaguar come to life!
zig build run

# Examples showcase
zig build examples

# WASM build for web prowling
zig build wasm

# Serve WASM demo
python3 serve_demo.py
# Then open http://localhost:8000/demo.html
```

Or add zgui to your build.zig:

```zig
const zgui_dep = b.dependency("zgui", .{ .target = target, .optimize = optimize });
const zgui = zgui_dep.module("zgui");
```

---

## 🖥️ Example Usage (Desktop)

```zig
const zgui = @import("zgui");

pub fn main() !void {
    var app = try zgui.App.init(.{ .title = "zgui - Powered by Jaguar" });
    defer app.deinit();

    app.window(.{ .title = "Dashboard", .width = 800, .height = 600 }) |win| {
        win.column(|col| {
            col.text("Welcome to zgui! 🐆");
            col.button("Unleash the Jaguar", .{ .onClick = on_button_click });
            col.graph({ .points = &[_]f32{ 1.0, 2.0, 1.5, 3.2 } });
        });
    };

    try app.run();
}

fn on_button_click(ctx: *zgui.Context) void {
    ctx.notify("The jaguar strikes! 🐆");
}
```

---

## 🌐 Example Usage (Browser/WASM)

```zig
const zgui = @import("zgui");

export fn main() void {
    zgui.web.start(.{
        .title = "zgui Web - Jaguar in the Browser",
        .root = |ui| {
            ui.row(|row| {
                row.text("The jaguar prowls the web! 🐆");
                row.button("Pounce Again", .{ .onClick = reload_page });
            });
        }
    });
}

fn reload_page(ctx: *zgui.Context) void {
    ctx.reload();
}
```

---

## � Current Status

**zgui v0.1.0-alpha** - The jaguar awakens!

✅ **The Jaguar's Current Territory:**
- Pure Zig implementation - no foreign dependencies
- Cross-platform hunting grounds (Desktop/WASM)
- Core widget pack ready to strike
- Event tracking with jaguar-like reflexes
- Adaptive camouflage (theming system)
- Web territory marked (WASM support)
- Demo applications showing the jaguar in action

🚧 **Stalking in Progress:**
- Enhanced window management (multiple territories)
- GPU acceleration for lightning-fast rendering
- Advanced layout strategies for perfect positioning
- Async runtime for non-blocking prowling

🔜 **Next Hunt:**
- Live reload - evolve without stopping
- Advanced widget pack expansion
- Native file system integration
- Performance benchmarks to prove jaguar supremacy

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

## 🤝 Join the Pack

Help zgui become the apex predator of GUI frameworks! PRs, issues, and new hunting strategies welcome.
See [`CONTRIBUTING.md`](CONTRIBUTING.md) for pack guidelines.

---

## 🐆 zgui - Where Jaguars and Zig Unite

Crafted with precision by [GhostKellz](https://github.com/ghostkellz)

