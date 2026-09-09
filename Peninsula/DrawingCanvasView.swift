import AppKit

final class DrawingCanvasView: NSView {
    var drawingState: DrawingState
    weak var overlayController: OverlayController?

    init(frame: NSRect, drawingState: DrawingState, overlayController: OverlayController) {
        self.drawingState = drawingState
        self.overlayController = overlayController
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high

        for stroke in drawingState.strokes {
            render(stroke, in: ctx)
        }
        if let current = drawingState.currentStroke {
            render(current, in: ctx)
        }
    }

    private func render(_ stroke: Stroke, in ctx: CGContext) {
        guard !stroke.points.isEmpty else { return }
        ctx.saveGState()
        ctx.setAlpha(stroke.opacity)
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setFillColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch stroke.tool {
        case .pen, .highlighter:
            drawSmooth(stroke.points, lineWidth: stroke.lineWidth, in: ctx)
        case .line:
            if let a = stroke.points.first, let b = stroke.points.last {
                ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            }
        case .arrow:
            if let a = stroke.points.first, let b = stroke.points.last, a != b {
                drawArrow(from: a, to: b, lineWidth: stroke.lineWidth, in: ctx)
            }
        case .rectangle:
            if let a = stroke.points.first, let b = stroke.points.last {
                ctx.stroke(rect(a, b))
            }
        case .ellipse:
            if let a = stroke.points.first, let b = stroke.points.last {
                ctx.strokeEllipse(in: rect(a, b))
            }
        case .eraser:
            break
        }
        ctx.restoreGState()
    }

    // MARK: - Smooth freehand (Laplacian + Bézier)

    private func drawSmooth(_ raw: [CGPoint], lineWidth: CGFloat, in ctx: CGContext) {
        if raw.count == 1 {
            ctx.fillEllipse(in: CGRect(
                x: raw[0].x - lineWidth / 2, y: raw[0].y - lineWidth / 2,
                width: lineWidth, height: lineWidth
            ))
            return
        }
        let pts = smoothed(raw)
        if pts.count < 3 {
            ctx.move(to: pts[0]); ctx.addLine(to: pts[pts.count - 1]); ctx.strokePath()
            return
        }

        ctx.move(to: pts[0])
        var pm = mid(pts[0], pts[1])
        ctx.addLine(to: pm)
        for i in 2..<pts.count {
            let m = mid(pts[i - 1], pts[i])
            ctx.addQuadCurve(to: m, control: pts[i - 1])
            pm = m
        }
        ctx.addLine(to: pts[pts.count - 1])
        ctx.strokePath()
    }

    private func smoothed(_ pts: [CGPoint]) -> [CGPoint] {
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

    // MARK: - Shape helpers

    private func drawArrow(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat, in ctx: CGContext) {
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let hl = max(15, lineWidth * 4)
        let ha: CGFloat = .pi / 6
        let p1 = CGPoint(x: b.x - hl * cos(angle - ha), y: b.y - hl * sin(angle - ha))
        let p2 = CGPoint(x: b.x - hl * cos(angle + ha), y: b.y - hl * sin(angle + ha))
        ctx.move(to: b); ctx.addLine(to: p1)
        ctx.move(to: b); ctx.addLine(to: p2)
        ctx.strokePath()
    }

    private func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let pt = convert(event.locationInWindow, from: nil)

        if drawingState.selectedTool == .eraser {
            performErase(at: pt)
            return
        }
        drawingState.startStroke(at: pt)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if drawingState.selectedTool == .eraser {
            performErase(at: pt)
            return
        }
        drawingState.continueStroke(to: pt)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if drawingState.selectedTool != .eraser {
            drawingState.finishStroke()
            needsDisplay = true
        }
    }

    private func performErase(at pt: CGPoint) {
        switch drawingState.eraserMode {
        case .stroke:
            drawingState.eraseStroke(near: pt)
        case .area:
            drawingState.eraseArea(at: pt, radius: max(8, drawingState.lineWidth * 2))
        }
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        if flags.contains(.command) && chars == "z" {
            if flags.contains(.shift) { drawingState.redo() } else { drawingState.undo() }
            overlayController?.refreshCanvases()
            return
        }
        if flags.contains(.command) && flags.contains(.shift) && chars == "x" {
            drawingState.clearAll()
            overlayController?.refreshCanvases()
            return
        }
        if event.keyCode == 53 {
            overlayController?.deactivate()
            return
        }

        let bare = flags.subtracting(.capsLock).isEmpty
        if bare {
            switch chars {
            case "1": drawingState.selectedTool = .pen
            case "2": drawingState.selectedTool = .highlighter
            case "3": drawingState.selectedTool = .arrow
            case "4": drawingState.selectedTool = .rectangle
            case "5": drawingState.selectedTool = .ellipse
            case "6": drawingState.selectedTool = .line
            case "7":
                if drawingState.selectedTool == .eraser {
                    drawingState.eraserMode = drawingState.eraserMode == .stroke ? .area : .stroke
                } else {
                    drawingState.selectedTool = .eraser
                }
            case "=", "+": drawingState.lineWidth = min(20, drawingState.lineWidth + 1)
            case "-", "_": drawingState.lineWidth = max(1, drawingState.lineWidth - 1)
            default: return
            }
        }
    }
}
