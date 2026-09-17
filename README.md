# Peninsula

Free, open-source screen annotation tool for macOS. Draw on your screen during presentations, meetings, or tutorials.

## Install

**Download:** Grab `Peninsula.zip` from [Releases](https://github.com/4isaiah/peninsula/releases), unzip, drag to Applications.

> First launch: right-click the app → Open (bypasses Gatekeeper since the app isn't signed).

**Build from source:**
```bash
git clone https://github.com/4isaiah/peninsula.git
cd peninsula
xcodebuild -scheme Peninsula -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/peninsula-*/Build/Products/Release/Peninsula.app
```

## Features

- **Drawing tools** — pen, highlighter, arrow, rectangle, ellipse, line, text, eraser
- **Shape smoothing** — freehand strokes are automatically smoothed
- **Color palettes** — 6 built-in palettes + custom palette support
- **Whiteboard / blackboard mode** — solid background for teaching
- **Screenshot capture** — select a region, copied to clipboard
- **Fading ink** — strokes that disappear after 3/5/10 seconds
- **Multi-monitor** — overlays span all connected displays
- **Menu bar app** — lives in your menu bar, out of the way

## Shortcuts

| Key | Action |
|-----|--------|
| `Cmd+Shift+D` | Toggle drawing overlay |
| `Cmd+Shift+P` | Open settings |
| `1-8` | Select tool |
| `+/-` | Brush size |
| `W` | Cycle whiteboard/blackboard |
| `S` | Screenshot mode |
| `F` | Toggle fading ink |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Cmd+Shift+X` | Clear all |
| `Esc` | Deactivate overlay |

## Requirements

macOS 14+

## License

MIT
