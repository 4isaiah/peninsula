import AppKit
import SwiftUI

// MARK: - Window

final class FloatingPaletteWindow: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Container

final class PaletteDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

// MARK: - View

struct FloatingPaletteView: View {
    @Bindable var drawingState: DrawingState
    var overlayController: OverlayController?
    var refocusCanvas: (() -> Void)?

    @State private var expanded = true
    @State private var dragMouseStart: NSPoint?
    @State private var dragOriginStart: NSPoint?
    @State private var suppressTap = false

    var body: some View {
        HStack(spacing: 0) {
            selectedToolButton

            if expanded {
                expandedContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.2, dampingFraction: 0.88), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onChange(of: expanded) { _, isExpanded in
            guard let window = paletteWindow else { return }
            if isExpanded {
                var frame = window.frame
                frame.size.width = 850
                if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })
                    ?? NSScreen.main {
                    let vis = screen.visibleFrame
                    frame.origin.x = max(vis.minX, min(frame.origin.x, vis.maxX - 850))
                }
                window.setFrame(frame, display: true)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard let window = paletteWindow else { return }
                    var frame = window.frame
                    frame.size.width = 48
                    window.setFrame(frame, display: true)
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    suppressTap = true
                    let mouse = NSEvent.mouseLocation
                    if dragMouseStart == nil {
                        dragMouseStart = mouse
                        dragOriginStart = paletteWindow?.frame.origin
                    }
                    guard let start = dragMouseStart,
                          let origin = dragOriginStart,
                          let window = paletteWindow else { return }
                    var x = origin.x + (mouse.x - start.x)
                    var y = origin.y + (mouse.y - start.y)
                    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                        ?? NSScreen.main {
                        let vis = screen.visibleFrame
                        let ws = window.frame.size
                        x = max(vis.minX, min(x, vis.maxX - ws.width))
                        y = max(vis.minY, min(y, vis.maxY - ws.height))
                    }
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
                .onEnded { _ in
                    dragMouseStart = nil
                    dragOriginStart = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        suppressTap = false
                    }
                }
        )
    }

    private var paletteWindow: NSWindow? {
        NSApp.windows.first { $0 is FloatingPaletteWindow }
    }

    private var selectedToolButton: some View {
        Button {
            if !expanded && !suppressTap {
                expanded = true
            }
        } label: {
            Image(systemName: drawingState.selectedTool.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(nsColor: drawingState.selectedColor))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .background(
                    Circle()
                        .fill(Color(nsColor: drawingState.selectedColor).opacity(expanded ? 0.15 : 0))
                )
        }
        .buttonStyle(.plain)
    }

    private var expandedContent: some View {
        HStack(spacing: 0) {
            divider
            drawToggle
            divider
            toolButtons
            divider
            colorDots
            divider
            sizeControl
            divider
            actionButtons
            divider
            featureButtons
            divider
            collapseButton
        }
    }

    private var drawToggle: some View {
        Button {
            overlayController?.toggle()
            refocusCanvas?()
        } label: {
            Image(systemName: drawingState.isActive ? "pencil.tip" : "pencil.slash")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .foregroundStyle(drawingState.isActive ? Color.primary : .secondary)
                .background(
                    Capsule()
                        .fill(drawingState.isActive ? Color.accentColor.opacity(0.2) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var toolButtons: some View {
        HStack(spacing: 1) {
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    drawingState.selectedTool = tool
                    if !drawingState.isActive { overlayController?.activate() }
                    refocusCanvas?()
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                        .background(
                            Capsule()
                                .fill(drawingState.selectedTool == tool
                                      ? Color(nsColor: drawingState.selectedColor).opacity(0.2)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colorDots: some View {
        let colors = drawingState.activePalette.nsColors
        return HStack(spacing: 1) {
            ForEach(0..<colors.count, id: \.self) { i in
                Button {
                    drawingState.selectedColor = colors[i]
                    refocusCanvas?()
                } label: {
                    Circle()
                        .fill(Color(nsColor: colors[i]))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected(colors[i])
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.12),
                                lineWidth: isSelected(colors[i]) ? 2 : 0.5
                            )
                        )
                        .frame(width: 22, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sizeControl: some View {
        HStack(spacing: 2) {
            Button {
                drawingState.lineWidth = max(1, drawingState.lineWidth - 1)
                refocusCanvas?()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("\(Int(drawingState.lineWidth))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 16)

            Button {
                drawingState.lineWidth = min(20, drawingState.lineWidth + 1)
                refocusCanvas?()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 1) {
            Button {
                drawingState.undo()
                overlayController?.refreshCanvases()
                refocusCanvas?()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(drawingState.strokes.isEmpty)

            Button {
                drawingState.redo()
                overlayController?.refreshCanvases()
                refocusCanvas?()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(drawingState.undoneStrokes.isEmpty)

            Button {
                drawingState.clearAll()
                overlayController?.refreshCanvases()
                refocusCanvas?()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(drawingState.strokes.isEmpty)
        }
    }

    private var featureButtons: some View {
        HStack(spacing: 1) {
            Button {
                drawingState.cycleBoardMode()
                overlayController?.refreshCanvases()
                refocusCanvas?()
            } label: {
                Image(systemName: drawingState.boardMode == .none
                      ? "rectangle.inset.filled"
                      : drawingState.boardMode == .white ? "sun.max" : "moon.fill")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
                    .foregroundStyle(drawingState.boardMode != .none ? Color.primary : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                drawingState.screenshotMode = true
                if !drawingState.isActive { overlayController?.activate() }
                refocusCanvas?()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                drawingState.fadingInkEnabled.toggle()
                refocusCanvas?()
            } label: {
                Image(systemName: drawingState.fadingInkEnabled ? "timer" : "timer")
                    .font(.system(size: 11))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
                    .foregroundStyle(drawingState.fadingInkEnabled ? Color.orange : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var collapseButton: some View {
        Button {
            expanded = false
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .medium))
                .frame(width: 24, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
    }

    private var divider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        guard let a = drawingState.selectedColor.usingColorSpace(.sRGB),
              let b = color.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
