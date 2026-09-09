import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var drawingState: DrawingState
    var overlayController: OverlayController?
    var dismiss: (() -> Void)?

    private let presetColors: [(String, NSColor)] = [
        ("Red", .systemRed),
        ("Orange", .systemOrange),
        ("Yellow", .systemYellow),
        ("Green", .systemGreen),
        ("Blue", .systemBlue),
        ("Purple", .systemPurple),
        ("White", .white),
        ("Black", .black),
    ]

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            toolSection
            Divider()
            colorSection
            Divider()
            sizeSection
            Divider()
            captureToggle
            Divider()
            actions
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 296)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text("Peninsula")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Toggle(isOn: Binding(
                get: { drawingState.isActive },
                set: { _ in
                    overlayController?.toggle()
                    if drawingState.isActive { dismiss?() }
                }
            )) {
                Text(drawingState.isActive ? "Drawing" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOOLS")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        drawingState.selectedTool = tool
                        if !drawingState.isActive {
                            overlayController?.activate()
                            dismiss?()
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 22)
                            Text(tool.shortcut)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.quaternary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(drawingState.selectedTool == tool
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if drawingState.selectedTool == .eraser {
                HStack(spacing: 8) {
                    Text("Eraser mode")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $drawingState.eraserMode) {
                        ForEach(EraserMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                .padding(.top, 2)
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                ForEach(presetColors, id: \.0) { name, color in
                    colorSwatch(color, label: name)
                }
            }

            if !drawingState.customColors.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(drawingState.customColors.enumerated()), id: \.offset) { i, color in
                        colorSwatch(color, label: "Custom")
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    drawingState.removeCustomColor(at: i)
                                }
                            }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    let panel = NSColorPanel.shared
                    panel.color = drawingState.selectedColor
                    panel.isContinuous = true
                    panel.setTarget(drawingState.colorPickerTarget)
                    panel.setAction(#selector(ColorPickerTarget.colorChanged(_:)))
                    panel.orderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Pick Color", systemImage: "eyedropper")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    drawingState.addCustomColor(drawingState.selectedColor)
                } label: {
                    Label("Save to Palette", systemImage: "plus.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SIZE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(drawingState.lineWidth)) pt")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $drawingState.lineWidth, in: 1...20, step: 1)
                .controlSize(.small)
        }
    }

    private var captureToggle: some View {
        Toggle(isOn: Binding(
            get: { drawingState.visibleInCapture },
            set: {
                drawingState.visibleInCapture = $0
                overlayController?.updateSharingType()
            }
        )) {
            Label(
                drawingState.visibleInCapture
                    ? "Visible in screen capture"
                    : "Hidden from screen capture",
                systemImage: drawingState.visibleInCapture ? "eye" : "eye.slash"
            )
            .font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                drawingState.undo()
                overlayController?.refreshCanvases()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11))
            }
            .disabled(drawingState.strokes.isEmpty)

            Button {
                drawingState.redo()
                overlayController?.refreshCanvases()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .font(.system(size: 11))
            }
            .disabled(drawingState.undoneStrokes.isEmpty)

            Spacer()

            Button(role: .destructive) {
                drawingState.clearAll()
                overlayController?.refreshCanvases()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .disabled(drawingState.strokes.isEmpty)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("⌘⇧D draw · ⌘⇧P menu · Esc exit")
                Text("⌘Z undo · ⌘⇧Z redo · ⌘⇧X clear")
            }
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11))
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func colorSwatch(_ color: NSColor, label: String) -> some View {
        Button {
            drawingState.selectedColor = color
        } label: {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().strokeBorder(
                        isSelected(color)
                            ? Color.accentColor
                            : Color.primary.opacity(0.12),
                        lineWidth: isSelected(color) ? 2.5 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        guard let a = drawingState.selectedColor.usingColorSpace(.sRGB),
              let b = color.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
