import AppKit

final class DrawingCanvasView: NSView, NSTextFieldDelegate {
    var drawingState: DrawingState
    weak var overlayController: OverlayController?
    private var activeTextField: NSTextField?
    private var trackingArea: NSTrackingArea?

    private var draggingTextIndex: Int?
    private var dragOffset: CGPoint = .zero
    private var screenshotStart: CGPoint?
    private var screenshotEnd: CGPoint?

    init(frame: NSRect, drawingState: DrawingState, overlayController: OverlayController) {
        self.drawingState = drawingState
        self.overlayController = overlayController
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Cursor via tracking area

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        if drawingState.screenshotMode {
            NSCursor.crosshair.set()
        } else if drawingState.selectedTool == .text {
            let pt = convert(event.locationInWindow, from: nil)
            if textStrokeIndex(at: pt) != nil {
                NSCursor.openHand.set()
            } else {
                NSCursor.iBeam.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        switch drawingState.boardMode {
        case .white:
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(bounds)
        case .black:
            ctx.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
            ctx.fill(bounds)
        case .none:
            break
        }

        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high

        for stroke in drawingState.strokes {
            render(stroke, in: ctx)
        }
        if let current = drawingState.currentStroke {
            render(current, in: ctx)
        }

        if drawingState.screenshotMode, let s = screenshotStart, let e = screenshotEnd {
            let sel = rect(s, e)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(sel)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fill(bounds)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(sel)
            ctx.restoreGState()
        }
    }

    private func render(_ stroke: Stroke, in ctx: CGContext) {
        guard !stroke.points.isEmpty else { return }

        var effectiveOpacity = stroke.opacity
        if let createdAt = stroke.createdAt, let duration = stroke.fadeDuration {
            let remaining = max(0, 1.0 - Date().timeIntervalSince(createdAt) / duration)
            if remaining <= 0 { return }
            effectiveOpacity *= remaining
        }

        ctx.saveGState()
        ctx.setAlpha(effectiveOpacity)
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setFillColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch stroke.tool {
        case .pen, .highlighter:
            let pts = stroke.smoothedPoints ?? Stroke.smooth(stroke.points)
            drawSmoothPath(pts, lineWidth: stroke.lineWidth, in: ctx)
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
        case .text:
            if let text = stroke.text, let origin = stroke.points.first {
                drawText(text, at: origin, color: stroke.color,
                         fontSize: stroke.fontSize ?? 18,
                         fontName: stroke.fontName ?? "Helvetica Neue",
                         opacity: effectiveOpacity)
            }
        case .eraser:
            break
        }
        ctx.restoreGState()
    }

    private func drawText(_ text: String, at point: CGPoint, color: NSColor,
                          fontSize: CGFloat, fontName: String, opacity: CGFloat = 1.0) {
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.withAlphaComponent(opacity)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: point)
    }

    // MARK: - Smooth freehand (Bézier)

    private func drawSmoothPath(_ pts: [CGPoint], lineWidth: CGFloat, in ctx: CGContext) {
        if pts.count == 1 {
            ctx.fillEllipse(in: CGRect(
                x: pts[0].x - lineWidth / 2, y: pts[0].y - lineWidth / 2,
                width: lineWidth, height: lineWidth
            ))
            return
        }
        if pts.count < 3 {
            ctx.move(to: pts[0]); ctx.addLine(to: pts[pts.count - 1]); ctx.strokePath()
            return
        }

        ctx.move(to: pts[0])
        ctx.addLine(to: mid(pts[0], pts[1]))
        for i in 2..<pts.count {
            let m = mid(pts[i - 1], pts[i])
            ctx.addQuadCurve(to: m, control: pts[i - 1])
        }
        ctx.addLine(to: pts[pts.count - 1])
        ctx.strokePath()
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

    // MARK: - Text hit testing & dragging

    private func textBoundingRect(for stroke: Stroke) -> CGRect? {
        guard stroke.tool == .text, let text = stroke.text, let origin = stroke.points.first else { return nil }
        let fontSize = stroke.fontSize ?? 18
        let fontName = stroke.fontName ?? "Helvetica Neue"
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    private func textStrokeIndex(at point: CGPoint) -> Int? {
        for i in stride(from: drawingState.strokes.count - 1, through: 0, by: -1) {
            guard let rect = textBoundingRect(for: drawingState.strokes[i]) else { continue }
            if rect.insetBy(dx: -10, dy: -10).contains(point) {
                return i
            }
        }
        return nil
    }

    // MARK: - Text input

    private func beginTextInput(at pt: CGPoint) {
        commitText()
        let fontSize = drawingState.textFontSize
        let font = NSFont(name: drawingState.textFontName, size: fontSize)
            ?? .systemFont(ofSize: fontSize)

        let field = NSTextField(frame: NSRect(x: pt.x, y: pt.y - fontSize - 4, width: 300, height: fontSize + 8))
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.font = font
        field.textColor = drawingState.selectedColor
        field.focusRingType = .none
        field.placeholderString = "Type here..."
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    func commitText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let origin = CGPoint(x: field.frame.origin.x, y: field.frame.origin.y)
            var stroke = Stroke(
                points: [origin],
                color: drawingState.selectedColor,
                lineWidth: drawingState.lineWidth,
                tool: .text,
                opacity: 1.0
            )
            stroke.text = text
            stroke.fontSize = drawingState.textFontSize
            stroke.fontName = drawingState.textFontName
            drawingState.strokes.append(stroke)
            drawingState.undoneStrokes.removeAll()
        }
        field.delegate = nil
        field.removeFromSuperview()
        activeTextField = nil
        needsDisplay = true
    }

    func cleanup() {
        commitText()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitText()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            activeTextField?.delegate = nil
            activeTextField?.removeFromSuperview()
            activeTextField = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let pt = convert(event.locationInWindow, from: nil)

        if drawingState.screenshotMode {
            screenshotStart = pt
            screenshotEnd = pt
            return
        }

        if drawingState.selectedTool != .text {
            commitText()
        }

        if drawingState.selectedTool == .text {
            if let index = textStrokeIndex(at: pt) {
                draggingTextIndex = index
                let origin = drawingState.strokes[index].points[0]
                dragOffset = CGPoint(x: pt.x - origin.x, y: pt.y - origin.y)
                NSCursor.closedHand.set()
                return
            }
            beginTextInput(at: pt)
            return
        }

        if drawingState.selectedTool == .eraser {
            performErase(at: pt)
            return
        }
        drawingState.startStroke(at: pt)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if drawingState.screenshotMode {
            screenshotEnd = pt
            needsDisplay = true
            return
        }

        if let index = draggingTextIndex, index < drawingState.strokes.count {
            drawingState.strokes[index].points[0] = CGPoint(
                x: pt.x - dragOffset.x,
                y: pt.y - dragOffset.y
            )
            needsDisplay = true
            overlayController?.refreshOtherCanvases(except: self)
            return
        }

        if drawingState.selectedTool == .text { return }
        if drawingState.selectedTool == .eraser {
            performErase(at: pt)
            return
        }
        drawingState.continueStroke(to: pt)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if drawingState.screenshotMode {
            if let s = screenshotStart, let e = screenshotEnd {
                let sel = rect(s, e)
                screenshotStart = nil
                screenshotEnd = nil
                drawingState.screenshotMode = false
                needsDisplay = true
                display()
                if sel.width > 5 && sel.height > 5 {
                    overlayController?.captureScreenshot(rect: sel, fromScreen: window?.screen)
                }
            }
            return
        }
        if draggingTextIndex != nil {
            draggingTextIndex = nil
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }
        if drawingState.selectedTool == .text { return }
        if drawingState.selectedTool != .eraser {
            drawingState.finishStroke()
            overlayController?.startFadeTimerIfNeeded()
            needsDisplay = true
        }
    }

    private func performErase(at pt: CGPoint) {
        drawingState.eraseStroke(near: pt)
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        if flags.contains(.command) && chars == "z" {
            if flags.contains(.shift) { drawingState.redo() } else { drawingState.undo() }
            overlayController?.refreshCanvases()
            overlayController?.startFadeTimerIfNeeded()
            return
        }
        if flags.contains(.command) && flags.contains(.shift) && chars == "x" {
            drawingState.clearAll()
            overlayController?.refreshCanvases()
            return
        }
        if event.keyCode == 53 {
            if drawingState.screenshotMode {
                drawingState.screenshotMode = false
                screenshotStart = nil
                screenshotEnd = nil
                needsDisplay = true
                return
            }
            commitText()
            overlayController?.deactivate()
            return
        }

        let bare = flags.subtracting(.capsLock).isEmpty
        if bare {
            switch chars {
            case "1": commitText(); drawingState.selectedTool = .pen
            case "2": commitText(); drawingState.selectedTool = .highlighter
            case "3": commitText(); drawingState.selectedTool = .arrow
            case "4": commitText(); drawingState.selectedTool = .rectangle
            case "5": commitText(); drawingState.selectedTool = .ellipse
            case "6": commitText(); drawingState.selectedTool = .line
            case "7": commitText(); drawingState.selectedTool = .text
            case "8": commitText(); drawingState.selectedTool = .eraser
            case "=", "+": drawingState.lineWidth = min(20, drawingState.lineWidth + 1)
            case "-", "_": drawingState.lineWidth = max(1, drawingState.lineWidth - 1)
            case "w": drawingState.cycleBoardMode(); overlayController?.refreshCanvases()
            case "s": drawingState.screenshotMode = true
            case "f": drawingState.fadingInkEnabled.toggle()
            case "t": overlayController?.togglePalette()
            default: return
            }
        }
    }
}
