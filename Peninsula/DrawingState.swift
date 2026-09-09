import SwiftUI
import AppKit

enum DrawingTool: String, CaseIterable {
    case pen
    case highlighter
    case arrow
    case rectangle
    case ellipse
    case line
    case eraser

    var shortcut: String {
        switch self {
        case .pen: "1"
        case .highlighter: "2"
        case .arrow: "3"
        case .rectangle: "4"
        case .ellipse: "5"
        case .line: "6"
        case .eraser: "7"
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
        case .eraser: "eraser"
        }
    }

    var isShape: Bool {
        self == .arrow || self == .rectangle || self == .ellipse || self == .line
    }
}

enum EraserMode: String, CaseIterable {
    case stroke
    case area
    var label: String { self == .stroke ? "Stroke" : "Area" }
    var icon: String { self == .stroke ? "eraser" : "eraser.line.dashed" }
}

struct Stroke {
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var tool: DrawingTool
    var opacity: CGFloat
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
    var eraserMode: EraserMode = .stroke

    var customColors: [NSColor] = []

    private var _colorPickerTarget: ColorPickerTarget?
    var colorPickerTarget: ColorPickerTarget {
        if let t = _colorPickerTarget { return t }
        let t = ColorPickerTarget(drawingState: self)
        _colorPickerTarget = t
        return t
    }

    init() {
        loadCustomColors()
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
        guard currentStroke != nil else { return }
        if currentStroke!.tool.isShape {
            if currentStroke!.points.count == 1 {
                currentStroke!.points.append(point)
            } else {
                currentStroke!.points[1] = point
            }
        } else {
            guard let last = currentStroke!.points.last else { return }
            if hypot(point.x - last.x, point.y - last.y) > 2.0 {
                currentStroke!.points.append(point)
            }
        }
    }

    func finishStroke() {
        guard let stroke = currentStroke else { return }
        strokes.append(stroke)
        undoneStrokes.removeAll()
        currentStroke = nil
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

    func eraseArea(at point: CGPoint, radius: CGFloat) {
        var rebuilt: [Stroke] = []
        var changed = false

        for stroke in strokes {
            let effectiveRadius = radius + stroke.lineWidth / 2
            var segments: [[CGPoint]] = []
            var current: [CGPoint] = []
            var hit = false

            for p in stroke.points {
                if hypot(p.x - point.x, p.y - point.y) < effectiveRadius {
                    if current.count >= 2 { segments.append(current) }
                    current = []
                    hit = true
                } else {
                    current.append(p)
                }
            }
            if current.count >= 2 { segments.append(current) }

            if hit {
                changed = true
                for seg in segments {
                    var s = stroke
                    s.points = seg
                    rebuilt.append(s)
                }
            } else {
                rebuilt.append(stroke)
            }
        }

        if changed { strokes = rebuilt }
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

    // MARK: - Custom Colors

    func addCustomColor(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        if !customColors.contains(where: { srgbEqual($0, srgb) }) {
            customColors.append(srgb)
            if customColors.count > 12 { customColors.removeFirst() }
            saveCustomColors()
        }
    }

    func removeCustomColor(at index: Int) {
        guard customColors.indices.contains(index) else { return }
        customColors.remove(at: index)
        saveCustomColors()
    }

    private func srgbEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ac = a.usingColorSpace(.sRGB), let bc = b.usingColorSpace(.sRGB) else { return false }
        return abs(ac.redComponent - bc.redComponent) < 0.01
            && abs(ac.greenComponent - bc.greenComponent) < 0.01
            && abs(ac.blueComponent - bc.blueComponent) < 0.01
    }

    private func saveCustomColors() {
        let data = customColors.compactMap { c -> [CGFloat]? in
            guard let s = c.usingColorSpace(.sRGB) else { return nil }
            return [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent]
        }
        UserDefaults.standard.set(data, forKey: "peninsula.customColors")
    }

    private func loadCustomColors() {
        guard let data = UserDefaults.standard.array(forKey: "peninsula.customColors") as? [[CGFloat]] else { return }
        customColors = data.map { c in
            NSColor(red: c[0], green: c[1], blue: c[2], alpha: c[3])
        }
    }
}

final class ColorPickerTarget: NSObject {
    let drawingState: DrawingState
    init(drawingState: DrawingState) { self.drawingState = drawingState }

    @objc func colorChanged(_ sender: NSColorPanel) {
        drawingState.selectedColor = sender.color
    }
}
