# Peninsula

A free, open-source screen drawing tool for macOS. Think Epic Pen, but for Mac.

I built this because I wanted a simple way to draw on my screen during presentations and calls — highlight stuff, sketch quick diagrams, point things out. Everything else I found was either paid, bloated, or Windows-only. So I made my own.

## What it does

- **Draw on your screen** — pen, highlighter, arrows, rectangles, circles, lines, text
- **Whiteboard / blackboard mode** — solid background for teaching or brainstorming
- **Screenshot capture** — select a region, goes straight to clipboard
- **Fading ink** — strokes disappear after a few seconds (great for presentations)
- **Color palettes** — 6 built-in, make your own
- **Multi-monitor** — works across all your displays
- **Stays out of your way** — lives in the menu bar, toggle on/off with a hotkey

## Tech

- Swift + SwiftUI + AppKit
- `NSPanel` overlays at screen-saver window level for click-through drawing
- Core Graphics for rendering (Bézier smoothing, shape tools)
- Carbon `RegisterEventHotKey` for global shortcuts
- `CGWindowListCreateImage` for screenshot capture
- `@Observable` for state management
- No dependencies, no frameworks, just Apple APIs

## Install

**Download:** Grab `Peninsula.zip` from [Releases](https://github.com/4isaiah/peninsula/releases), unzip, drag to Applications.

> First launch: right-click the app → **Open** (it's unsigned, so macOS will ask you to confirm once).

**Build from source:**

```bash
git clone https://github.com/4isaiah/peninsula.git
cd peninsula
xcodebuild -scheme Peninsula -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/peninsula-*/Build/Products/Release/Peninsula.app
```

Requires macOS 14+ and Xcode 15+.

## Usage

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+D` | Toggle drawing on/off |
| `Cmd+Shift+P` | Open settings |
| `1`–`8` | Switch tools |
| `+` / `-` | Brush size |
| `W` | Whiteboard / blackboard |
| `S` | Screenshot mode |
| `F` | Fading ink |
| `T` | Toggle floating toolbar |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / redo |
| `Esc` | Deactivate |

## License

MIT — do whatever you want with it. Free forever.
