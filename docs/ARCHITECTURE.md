# zgui Architecture Overview

This document tracks the evolving structure of zgui as we layer in runtime,
rendering, and text capabilities. Sprint 2 introduces the foundational
abstractions and integrates the new dependency set.

## Module Layout

```
src/
├── runtime/
│   ├── async.zig       # thin wrapper around optional zsync runtime
│   ├── events.zig      # high-level runtime event queue helpers
│   └── loop.zig        # zigzag-driven event loop with Wayland integration
├── text/
│   ├── fonts.zig       # font manager backed by zfont with default discovery
│   └── layout.zig      # text shaping entry point producing glyph placement runs
├── main.zig            # demo executable entry point
└── root.zig            # library entry that re-exports runtime/text modules
```

### Runtime Layer

* `wzl` supplies Wayland bindings (connection, surfaces, event dispatch).
* `zigzag` provides the cross-platform event loop (libxev-style backend).
* `zsync` will plug into the runtime to run async tasks once the executor
  wiring is complete.
* `src/runtime/loop.zig` encapsulates these dependencies so the rest of the
   codebase interacts with a simple `Runtime` facade. `Runtime.init` now wires
   the Wayland connection into a zigzag `EventLoop`, installs the socket watch,
   exposes an event queue, and returns a heap-managed runtime handle.
* `src/runtime/async.zig` is an `AsyncBridge` that can wrap an external
   `zsync.runtime.Runtime` or spin up an internal one when `enable_async` is set,
   providing `Runtime.runAsyncTask` as the scheduling hook for background work.
* `src/runtime/events.zig` offers a lightweight queue of semantic runtime
   events (dispatch ticks, connection loss, I/O faults) so upper layers can react
   without poking Wayland internals directly.

Future work: expand the async bridge to share executor state with widget task
graphs, surface frame callbacks into the widget layer, and translate Wayland
seat/pointer/keyboard messages into structured input events.

### Text Stack

* `zfont` handles font parsing, metrics, and glyph rasterization (CPU path).
* `gcode` will augment Unicode traversal utilities (grapheme clusters, bidi, etc.).
* `src/text/fonts.zig` now manages font registries, owns parsed font objects, locates
   a default font via `ZGUI_FONT_PATH` or common platform directories, and exposes
   glyph bitmaps through zfont's renderer for atlas population.
* `src/text/layout.zig` produces positioned glyph runs for the renderer, combining
   kerning and advance widths into per-glyph placements with rudimentary multi-line
   support.

A renderer-agnostic glyph atlas builder will eventually sit between the text
stack and GPU backends.

## Dependency Topology

```
          +---------+
          |  zigzag |
          +----+----+
               |
          +----v----+        +--------+
          | runtime |------->|  wzl   |
          +----+----+        +--------+
               |
          +----v----+
          | widgets |  (future)
          +----+----+
               |
      +--------v--------+
      | text (fonts/layout) |
      +--+-------------+---+
         |             |
     +---v---+     +---v---+
     | zfont |     | gcode |
     +-------+     +-------+
```

## Immediate Priorities

1. Flesh out `Runtime` so it owns zigzag's loop instance and integrates the
   Wayland dispatcher from wzl.
2. Provide adapter hooks for zsync so async tasks can share the same event
   loop without busy-waiting.
3. Extend the text stack's shaping to incorporate full Unicode segmentation via
   `gcode`, richer fallback chains, and glyph atlasing before wiring widgets to
   real rendering.
4. Expand the widget layer to consume the runtime and text services, using the
   CPU renderer as an interim target.

## Sprint 3 Outlook

* **Widget text integration:** feed `TextLayout` line metrics directly into the
  widget tree, producing selection/highlight data alongside glyph runs.
* **Atlas baking:** build a CPU glyph atlas cache that consumes the new
  `FontManager.getGlyphImage` helper and surfaces atlas handles to renderers.
* **Input channeling:** translate Wayland pointer/keyboard events into a widget
  event stream, including IME-friendly text input plumbing.
* **Demo polish:** ship a stress-test demo that exercises multi-script text,
  bidi layout, and fallback chains while showcasing async runtime hooks.

This outline will be updated as each sprint adds capabilities.
