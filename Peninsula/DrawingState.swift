import SwiftUI
import AppKit

enum DrawingTool: String, CaseIterable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case line
    case text
    case eraser

    var shortcut: String {
        switch self {
        case .pen: "1"
        case .highlighter: "2"
        case .arrow: "3"
        case .rectangle: "4"
        case .ellipse: "5"
        case .line: "6"
        case .text: "7"
        case .eraser: "8"
        }
    }

    var icon: String {
        switch self {
        case .pen: "pencil"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .eraser: "eraser"
        }
    }

    var isShape: Bool {
        self == .arrow || self == .rectangle || self == .ellipse || self == .line
    }
}

enum BoardMode { case none, white, black }

enum FadeDuration: Double, CaseIterable {
    case short = 3.0
    case medium = 5.0
    case long = 10.0
    var label: String {
        switch self {
        case .short: "3s"
        case .medium: "5s"
        case .long: "10s"
        }
    }
}

struct Stroke {
    var points: [CGPoint]
    var smoothedPoints: [CGPoint]?
    var color: NSColor
    var lineWidth: CGFloat
    var tool: DrawingTool
    var opacity: CGFloat
    var text: String?
    var fontSize: CGFloat?
    var fontName: String?
    var createdAt: Date?
    var fadeDuration: TimeInterval?

    static func smooth(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count >= 3 else { return pts }
        var r = pts
        for _ in 0..<3 {
            var s = [r[0]]
            for i in 1..<r.count - 1 {
                s.append(CGPoint(
                    x: r[i - 1].x * 0.2 + r[i].x * 0.6 + r[i + 1].x * 0.2,
                    y: r[i - 1].y * 0.2 + r[i].y * 0.6 + r[i + 1].y * 0.2
                ))
            }
            s.append(r[r.count - 1])
            r = s
        }
        return r
    }
}

// MARK: - Color Palettes

struct ColorPalette: Codable, Identifiable {
    var id: String
    var name: String
    var colors: [[CGFloat]]

    var nsColors: [NSColor] {
        colors.map { c in
            NSColor(red: c[0], green: c[1], blue: c[2], alpha: c.count > 3 ? c[3] : 1.0)
        }
    }

    static let builtIn: [ColorPalette] = [
        ColorPalette(id: "default", name: "Default", colors: [
            [1.0, 0.23, 0.19], [1.0, 0.58, 0.0], [1.0, 0.84, 0.0],
            [0.20, 0.78, 0.35], [0.0, 0.48, 1.0], [0.69, 0.32, 0.87],
            [1.0, 1.0, 1.0], [0.0, 0.0, 0.0],
        ]),
        ColorPalette(id: "pastel", name: "Pastel", colors: [
            [1.0, 0.71, 0.76], [1.0, 0.85, 0.73], [1.0, 0.97, 0.75],
            [0.75, 0.94, 0.75], [0.68, 0.85, 0.90], [0.80, 0.75, 0.90],
            [0.96, 0.76, 0.90], [0.85, 0.85, 0.85],
        ]),
        ColorPalette(id: "neon", name: "Neon", colors: [
            [1.0, 0.07, 0.28], [1.0, 0.35, 0.0], [0.95, 1.0, 0.0],
            [0.0, 1.0, 0.40], [0.0, 0.75, 1.0], [0.58, 0.0, 1.0],
            [1.0, 0.0, 0.85], [1.0, 1.0, 1.0],
        ]),
        ColorPalette(id: "earth", name: "Earth", colors: [
            [0.55, 0.27, 0.07], [0.72, 0.53, 0.04], [0.82, 0.71, 0.55],
            [0.42, 0.56, 0.14], [0.33, 0.42, 0.18], [0.60, 0.40, 0.30],
            [0.36, 0.25, 0.20], [0.20, 0.20, 0.20],
        ]),
        ColorPalette(id: "ocean", name: "Ocean", colors: [
            [0.0, 0.30, 0.53], [0.0, 0.48, 0.65], [0.0, 0.63, 0.78],
            [0.25, 0.80, 0.82], [0.60, 0.92, 0.92], [0.17, 0.24, 0.44],
            [0.90, 0.95, 0.98], [0.10, 0.10, 0.10],
        ]),
        ColorPalette(id: "monochrome", name: "Mono", colors: [
            [0.0, 0.0, 0.0], [0.20, 0.20, 0.20], [0.35, 0.35, 0.35],
            [0.50, 0.50, 0.50], [0.65, 0.65, 0.65], [0.80, 0.80, 0.80],
            [0.92, 0.92, 0.92], [1.0, 1.0, 1.0],
        ]),
    ]
}

@Observable
final class DrawingState {
    var strokes: [Stroke] = []
    var currentStroke: Stroke?
    var undoneStrokes: [Stroke] = []

    var selectedTool: DrawingTool = .pen
    var selectedColor: NSColor = .systemRed
    var lineWidth: CGFloat = 3
    var isActive = false
    var visibleInCapture = true
    var textFontSize: CGFloat = 18
    var textFontName: String = "Helvetica Neue"

    var boardMode: BoardMode = .none
    var fadingInkEnabled = false
    var fadeDuration: FadeDuration = .medium
    var screenshotMode = false

    var activePaletteId: String = "default"
    var customPalettes: [ColorPalette] = []
    var editingPaletteId: String?
    var editingColorIndex: Int?

    var activePalette: ColorPalette {
        let all = ColorPalette.builtIn + customPalettes
        return all.first { $0.id == activePaletteId } ?? ColorPalette.builtIn[0]
    }

    init() {
        loadPalettes()
    }

    func selectPalette(_ id: String) {
        activePaletteId = id
        UserDefaults.standard.set(id, forKey: "peninsula.activePalette")
    }

    func addCustomPalette(name: String, colors: [NSColor]) {
        let id = "custom_\(Int(Date().timeIntervalSince1970))"
        let colorData = colors.compactMap { c -> [CGFloat]? in
            guard let s = c.usingColorSpace(.sRGB) else { return nil }
            return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent]
        }
        customPalettes.append(ColorPalette(id: id, name: name, colors: colorData))
        savePalettes()
    }

    func removeCustomPalette(_ id: String) {
        customPalettes.removeAll { $0.id == id }
        if activePaletteId == id { activePaletteId = "default" }
        savePalettes()
    }

    func renameCustomPalette(_ id: String, name: String) {
        guard let i = customPalettes.firstIndex(where: { $0.id == id }) else { return }
        customPalettes[i].name = name
        savePalettes()
    }

    func updatePaletteColor(_ color: NSColor) {
        guard let paletteId = editingPaletteId,
              let index = editingColorIndex,
              let pi = customPalettes.firstIndex(where: { $0.id == paletteId }),
              index < customPalettes[pi].colors.count,
              let srgb = color.usingColorSpace(.sRGB) else { return }
        customPalettes[pi].colors[index] = [
            srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent
        ]
        savePalettes()
    }

    func startStroke(at point: CGPoint) {
        let opacity: CGFloat = selectedTool == .highlighter ? 0.35 : 1.0
        let width: CGFloat = selectedTool == .highlighter ? lineWidth * 4 : lineWidth
        currentStroke = Stroke(
            points: [point],
            color: selectedColor,
            lineWidth: width,
            tool: selectedTool,
            opacity: opacity
        )
    }

    func continueStroke(to point: CGPoint) {
        guard var stroke = currentStroke else { return }
        if stroke.tool.isShape {
            if stroke.points.count == 1 {
                stroke.points.append(point)
            } else {
                stroke.points[1] = point
            }
        } else {
            guard let last = stroke.points.last else { return }
            if hypot(point.x - last.x, point.y - last.y) > 2.0 {
                stroke.points.append(point)
            }
        }
        currentStroke = stroke
    }

    func finishStroke() {
        guard var stroke = currentStroke else { return }
        if stroke.tool == .pen || stroke.tool == .highlighter {
            stroke.smoothedPoints = Stroke.smooth(stroke.points)
        }
        if fadingInkEnabled {
            stroke.createdAt = Date()
            stroke.fadeDuration = fadeDuration.rawValue
        }
        strokes.append(stroke)
        undoneStrokes.removeAll()
        currentStroke = nil
    }

    func removeExpiredStrokes() {
        strokes.removeAll { stroke in
            guard let createdAt = stroke.createdAt, let duration = stroke.fadeDuration else { return false }
            return Date().timeIntervalSince(createdAt) >= duration
        }
    }

    func cycleBoardMode() {
        switch boardMode {
        case .none: boardMode = .white
        case .white: boardMode = .black
        case .black: boardMode = .none
        }
    }

    @discardableResult
    func eraseStroke(near point: CGPoint) -> Bool {
        if let index = strokes.lastIndex(where: { stroke in
            let threshold: CGFloat = 15 + stroke.lineWidth / 2
            return stroke.points.contains { p in
                hypot(p.x - point.x, p.y - point.y) < threshold
            }
        }) {
            strokes.remove(at: index)
            return true
        }
        return false
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        undoneStrokes.append(last)
    }

    func redo() {
        guard let last = undoneStrokes.popLast() else { return }
        strokes.append(last)
    }

    func clearAll() {
        strokes.removeAll()
        undoneStrokes.removeAll()
        currentStroke = nil
    }

    // MARK: - Persistence

    private func savePalettes() {
        if let data = try? JSONEncoder().encode(customPalettes) {
            UserDefaults.standard.set(data, forKey: "peninsula.customPalettes")
        }
        UserDefaults.standard.set(activePaletteId, forKey: "peninsula.activePalette")
    }

    private func loadPalettes() {
        activePaletteId = UserDefaults.standard.string(forKey: "peninsula.activePalette") ?? "default"
        if let data = UserDefaults.standard.data(forKey: "peninsula.customPalettes"),
           let palettes = try? JSONDecoder().decode([ColorPalette].self, from: data) {
            customPalettes = palettes
        }
    }
}
