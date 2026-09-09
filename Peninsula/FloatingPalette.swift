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

// MARK: - View

struct FloatingPaletteView: View {
    @Bindable var drawingState: DrawingState
    var overlayController: OverlayController?
    var moveWindow: ((NSPoint) -> Void)?
    var refocusCanvas: (() -> Void)?

    @State private var expanded = true
    @State private var locked = false

    private let quickColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .white, .black,
    ]

    var body: some View {
        HStack(spacing: 0) {
            selectedToolButton

            if expanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.25, dampingFraction: 0.88), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { _ in
                    if !locked { moveWindow?(NSEvent.mouseLocation) }
                }
        )
    }

    // MARK: - Selected tool (always visible)

    private var selectedToolButton: some View {
        Button {
            if !expanded {
                expanded = true
            } else {
                if !drawingState.isActive { overlayController?.activate() }
                refocusCanvas?()
            }
        } label: {
            Image(systemName: drawingState.selectedTool.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(expanded ? 0.2 : 0))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        HStack(spacing: 0) {
            divider
            toolButtons
            divider
            colorDots
            divider
            sizeControl
            divider
            actionButtons
            divider
            barControls
        }
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(DrawingTool.allCases, id: \.self) { tool in
                if tool != drawingState.selectedTool {
                    Button {
                        drawingState.selectedTool = tool
                        if !drawingState.isActive { overlayController?.activate() }
                        refocusCanvas?()
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }

            if drawingState.selectedTool == .eraser {
                Button {
                    drawingState.eraserMode = drawingState.eraserMode == .stroke ? .area : .stroke
                    refocusCanvas?()
                } label: {
                    Text(drawingState.eraserMode == .stroke ? "S" : "A")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colorDots: some View {
        HStack(spacing: 3) {
            ForEach(0..<quickColors.count, id: \.self) { i in
                Button {
                    drawingState.selectedColor = quickColors[i]
                    refocusCanvas?()
                } label: {
                    Circle()
                        .fill(Color(nsColor: quickColors[i]))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected(quickColors[i])
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.12),
                                lineWidth: isSelected(quickColors[i]) ? 2 : 0.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sizeControl: some View {
        HStack(spacing: 4) {
            Button {
                drawingState.lineWidth = max(1, drawingState.lineWidth - 1)
                refocusCanvas?()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
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
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button {
                drawingState.undo()
                overlayController?.refreshCanvases()
                refocusCanvas?()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .frame(width: 26, height: 28)
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
                    .frame(width: 26, height: 28)
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
                    .frame(width: 26, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(drawingState.strokes.isEmpty)
        }
    }

    private var barControls: some View {
        HStack(spacing: 2) {
            Button {
                locked.toggle()
            } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10))
                    .frame(width: 24, height: 28)
                    .foregroundStyle(locked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                expanded = false
            } label: {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var divider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 5)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        guard let a = drawingState.selectedColor.usingColorSpace(.sRGB),
              let b = color.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
