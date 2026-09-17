import SwiftUI
import AppKit

struct MenuBarView: View {
    @Bindable var drawingState: DrawingState
    var overlayController: OverlayController?
    var dismiss: (() -> Void)?

    enum Page { case main, settings, palettes }
    @State private var page: Page = .main

    var body: some View {
        VStack(spacing: 12) {
            switch page {
            case .main: mainView
            case .settings: settingsView
            case .palettes: palettesView
            }
        }
        .padding(16)
        .frame(width: 296)
    }

    // MARK: - Main

    private var mainView: some View {
        Group {
            header
            Divider()
            toolSection
            Divider()
            colorSection
            Divider()
            sizeSection
            Divider()
            textSection
            Divider()
            featureSection
            Divider()
            captureToggle
            Divider()
            paletteToggle
            Divider()
            actions
            Divider()
            footer
        }
    }

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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
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
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COLOR")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                Text("·")
                    .foregroundStyle(.quaternary)

                Button {
                    page = .palettes
                } label: {
                    Text(drawingState.activePalette.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    overlayController?.openColorPicker()
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            let colors = drawingState.activePalette.nsColors
            HStack(spacing: 6) {
                ForEach(0..<colors.count, id: \.self) { i in
                    colorSwatch(colors[i])
                }
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

    private let availableFonts: [String] = {
        let preferred = [
            "Helvetica Neue", "SF Pro", "Avenir Next", "Futura",
            "Gill Sans", "Menlo", "Monaco", "Courier New",
            "Georgia", "Times New Roman", "Palatino", "Baskerville",
            "American Typewriter", "Marker Felt", "Noteworthy"
        ]
        let all = NSFontManager.shared.availableFontFamilies
        return preferred.filter { all.contains($0) } + ["System"]
    }()

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEXT")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                Picker("Font", selection: $drawingState.textFontName) {
                    ForEach(availableFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker("Size", selection: $drawingState.textFontSize) {
                    ForEach([12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72], id: \.self) { size in
                        Text("\(size) pt").tag(CGFloat(size))
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }
        }
    }

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FEATURES")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                Button {
                    drawingState.cycleBoardMode()
                    overlayController?.refreshCanvases()
                } label: {
                    Label {
                        switch drawingState.boardMode {
                        case .none: Text("Board Off")
                        case .white: Text("Whiteboard")
                        case .black: Text("Blackboard")
                        }
                    } icon: {
                        Image(systemName: drawingState.boardMode == .none
                              ? "rectangle.inset.filled"
                              : drawingState.boardMode == .white ? "sun.max" : "moon.fill")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(drawingState.boardMode != .none ? .primary : .secondary)

                Spacer()

                Button {
                    drawingState.screenshotMode = true
                    if !drawingState.isActive {
                        overlayController?.activate()
                    }
                    dismiss?()
                } label: {
                    Label("Screenshot", systemImage: "camera.viewfinder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Toggle(isOn: $drawingState.fadingInkEnabled) {
                    Label("Fading ink", systemImage: "timer")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                if drawingState.fadingInkEnabled {
                    Picker("", selection: $drawingState.fadeDuration) {
                        ForEach(FadeDuration.allCases, id: \.self) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 60)
                }
            }
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

    @State private var paletteOn = true

    private var paletteToggle: some View {
        Toggle(isOn: Binding(
            get: { overlayController?.paletteVisible ?? true },
            set: { _ in
                overlayController?.togglePalette()
                paletteOn.toggle()
            }
        )) {
            Label("Floating toolbar", systemImage: "paintpalette")
                .font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            Button {
                drawingState.undo()
                overlayController?.refreshCanvases()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11))
            }
            .disabled(drawingState.strokes.isEmpty)

            Spacer()

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
            Button {
                page = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .font(.system(size: 11))
                .controlSize(.small)
        }
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(spacing: 12) {
            pageHeader("Settings")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SHORTCUTS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)

                    shortcutRow("Toggle drawing", shortcut: "⌘⇧D")
                    shortcutRow("Open menu", shortcut: "⌘⇧P")
                    shortcutRow("Exit drawing", shortcut: "Esc")
                    shortcutRow("Undo", shortcut: "⌘Z")
                    shortcutRow("Redo", shortcut: "⌘⇧Z")
                    shortcutRow("Clear all", shortcut: "⌘⇧X")

                    Divider()

                    Text("TOOL SHORTCUTS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)

                    ForEach(DrawingTool.allCases, id: \.self) { tool in
                        shortcutRow(tool.rawValue.capitalized, shortcut: tool.shortcut, icon: tool.icon)
                    }

                    shortcutRow("Size up", shortcut: "+")
                    shortcutRow("Size down", shortcut: "−")
                    shortcutRow("Whiteboard", shortcut: "W", icon: "rectangle.inset.filled")
                    shortcutRow("Screenshot", shortcut: "S", icon: "camera.viewfinder")
                    shortcutRow("Fading ink", shortcut: "F", icon: "timer")
                    shortcutRow("Toggle toolbar", shortcut: "T", icon: "paintpalette")

                    Divider()

                    Text("ABOUT")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)

                    HStack {
                        Text("Peninsula")
                            .font(.system(size: 11))
                        Spacer()
                        Text("v1.0")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 340)
        }
    }

    // MARK: - Palettes

    private var palettesView: some View {
        VStack(spacing: 12) {
            pageHeader("Color Palettes")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("PRESETS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)

                    ForEach(ColorPalette.builtIn) { palette in
                        paletteRow(palette)
                    }

                    if !drawingState.customPalettes.isEmpty {
                        Divider()

                        Text("CUSTOM · tap a color to edit")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)

                        ForEach(drawingState.customPalettes) { palette in
                            editablePaletteRow(palette)
                                .contextMenu {
                                    Button("Rename") { startRename(palette) }
                                    Button("Delete", role: .destructive) {
                                        drawingState.removeCustomPalette(palette.id)
                                    }
                                }
                        }
                    }

                    Divider()

                    Button {
                        createPaletteFromCurrentColor()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("New palette from color picker")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: 340)
        }
    }


    private func paletteRow(_ palette: ColorPalette) -> some View {
        Button {
            drawingState.selectPalette(palette.id)
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<palette.nsColors.count, id: \.self) { i in
                        Circle()
                            .fill(Color(nsColor: palette.nsColors[i]))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                }

                Spacer()

                Text(palette.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if drawingState.activePaletteId == palette.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(drawingState.activePaletteId == palette.id
                          ? Color.accentColor.opacity(0.08)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func editablePaletteRow(_ palette: ColorPalette) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<palette.nsColors.count, id: \.self) { i in
                    let editing = drawingState.editingPaletteId == palette.id && drawingState.editingColorIndex == i
                    Button {
                        drawingState.selectPalette(palette.id)
                        overlayController?.openColorPicker(
                            editingPaletteId: palette.id,
                            colorIndex: i,
                            startColor: palette.nsColors[i]
                        )
                    } label: {
                        Circle()
                            .fill(Color(nsColor: palette.nsColors[i]))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(
                                    editing ? Color.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: editing ? 2 : 0.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if renamingPaletteId == palette.id {
                TextField("Name", text: $renamingPaletteName)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .frame(width: 70)
                    .onSubmit { commitRename(palette.id) }
            } else {
                Text(palette.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if drawingState.activePaletteId == palette.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { drawingState.selectPalette(palette.id) }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(drawingState.activePaletteId == palette.id
                      ? Color.accentColor.opacity(0.08)
                      : Color.clear)
        )
    }

    @State private var renamingPaletteId: String?
    @State private var renamingPaletteName = ""

    private func startRename(_ palette: ColorPalette) {
        renamingPaletteId = palette.id
        renamingPaletteName = palette.name
    }

    private func commitRename(_ id: String) {
        let trimmed = renamingPaletteName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            drawingState.renameCustomPalette(id, name: trimmed)
        }
        renamingPaletteId = nil
    }

    private func createPaletteFromCurrentColor() {
        let base = drawingState.selectedColor.usingColorSpace(.sRGB) ?? drawingState.selectedColor
        let h = base.hueComponent
        let colors: [NSColor] = stride(from: 0.0, to: 1.0, by: 0.125).map { offset in
            NSColor(hue: (h + offset).truncatingRemainder(dividingBy: 1.0),
                    saturation: base.saturationComponent,
                    brightness: base.brightnessComponent,
                    alpha: 1.0)
        }
        drawingState.addCustomPalette(name: "Custom \(drawingState.customPalettes.count + 1)", colors: colors)
    }

    // MARK: - Shared components

    private func pageHeader(_ title: String) -> some View {
        HStack {
            Button {
                page = .main
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
    }

    private func shortcutRow(_ label: String, shortcut: String, icon: String? = nil) -> some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    // MARK: - Helpers

    private func colorSwatch(_ color: NSColor) -> some View {
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
    }

    private func isSelected(_ color: NSColor) -> Bool {
        guard let a = drawingState.selectedColor.usingColorSpace(.sRGB),
              let b = color.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }
}
