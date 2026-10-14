import AppKit
import Carbon.HIToolbox
import SwiftUI

final class OverlayController {
    let drawingState: DrawingState
    weak var appDelegate: AppDelegate?
    private(set) var overlayWindows: [OverlayWindow] = []
    private(set) var canvasViews: [DrawingCanvasView] = []
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private(set) var hotKeyStatus: [UInt32: OSStatus] = [:]
    private var previousApp: NSRunningApplication?
    private var eventHandlerRef: EventHandlerRef?

    private var paletteWindow: FloatingPaletteWindow?
    private var colorObserver: Any?
    private var screenObserver: Any?
    private var fadeTimer: Timer?

    var paletteVisible: Bool {
        paletteWindow?.isVisible ?? false
    }

    init(drawingState: DrawingState, appDelegate: AppDelegate) {
        self.drawingState = drawingState
        self.appDelegate = appDelegate
        registerGlobalHotKeys()
        syncClearHotKey()
        showPalette()
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let color = NSColorPanel.shared.color
            if self.drawingState.editingPaletteId != nil {
                self.drawingState.updatePaletteColor(color)
            } else {
                self.drawingState.selectedColor = color
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    func openColorPicker(editingPaletteId: String? = nil, colorIndex: Int? = nil, startColor: NSColor? = nil) {
        drawingState.editingPaletteId = editingPaletteId
        drawingState.editingColorIndex = colorIndex
        let panel = NSColorPanel.shared
        panel.color = startColor ?? drawingState.selectedColor
        panel.isContinuous = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func togglePalette() {
        if let window = paletteWindow, window.isVisible {
            window.orderOut(nil)
        } else if let window = paletteWindow {
            window.orderFrontRegardless()
        } else {
            showPalette()
        }
    }

    // MARK: - Overlay

    func toggle() {
        if drawingState.isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !drawingState.isActive else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front != .current {
            previousApp = front
        }
        drawingState.isActive = true
        rebuildOverlayWindows()
        NSApp.activate(ignoringOtherApps: true)
        if let first = overlayWindows.first {
            first.makeKey()
            first.contentView?.becomeFirstResponder()
        }
    }

    private func rebuildOverlayWindows() {
        let old = overlayWindows
        overlayWindows.removeAll()
        canvasViews.removeAll()
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let canvas = DrawingCanvasView(
                frame: screen.frame,
                drawingState: drawingState,
                overlayController: self
            )
            canvas.autoresizingMask = [.width, .height]
            window.contentView = canvas
            window.ignoresMouseEvents = !drawingState.isActive
            window.sharingType = drawingState.visibleInCapture ? .readWrite : .none
            window.orderFrontRegardless()
            overlayWindows.append(window)
            canvasViews.append(canvas)
        }
        for window in old { window.orderOut(nil) }
    }

    private func handleScreenChange() {
        if drawingState.isActive {
            rebuildOverlayWindows()
            NSApp.activate(ignoringOtherApps: true)
            if let first = overlayWindows.first {
                first.makeKey()
                first.contentView?.becomeFirstResponder()
            }
        } else if !overlayWindows.isEmpty {
            rebuildOverlayWindows()
        }
    }

    func deactivate() {
        guard drawingState.isActive else { return }
        drawingState.isActive = false
        drawingState.screenshotMode = false

        for canvas in canvasViews {
            canvas.cleanup()
        }
        for window in overlayWindows {
            window.ignoresMouseEvents = true
        }
        NSCursor.arrow.set()
        // Hand the keyboard and cursor straight back to the app the user was in.
        if let previousApp {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate(from: .current, options: [])
        }
        previousApp = nil
    }

    func refreshCanvases() {
        for canvas in canvasViews {
            canvas.needsDisplay = true
        }
    }

    func refreshOtherCanvases(except source: DrawingCanvasView) {
        for canvas in canvasViews where canvas !== source {
            canvas.needsDisplay = true
        }
    }

    func refocusCanvas() {
        guard drawingState.isActive else { return }
        for canvas in canvasViews {
            if drawingState.selectedTool != .text {
                canvas.commitText()
            }
        }
        if let first = overlayWindows.first {
            first.makeKey()
            first.contentView?.becomeFirstResponder()
        }
    }

    func updateSharingType() {
        let type: NSWindow.SharingType = drawingState.visibleInCapture ? .readWrite : .none
        for window in overlayWindows {
            window.sharingType = type
        }
    }

    // MARK: - Screenshot

    func captureScreenshot(rect: CGRect, fromScreen screen: NSScreen?) {
        guard let screen, let mainScreen = NSScreen.screens.first else { return }
        let mainHeight = mainScreen.frame.height
        let gx = screen.frame.origin.x + rect.origin.x
        let gy = screen.frame.origin.y + rect.origin.y
        let displayRect = CGRect(
            x: gx,
            y: mainHeight - gy - rect.height,
            width: rect.width,
            height: rect.height
        )

        let wasHidden = !drawingState.visibleInCapture
        if wasHidden {
            for window in overlayWindows { window.sharingType = .readWrite }
        }

        guard let cgImage = CGWindowListCreateImage(
            displayRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]
        ) else {
            if wasHidden { updateSharingType() }
            return
        }

        if wasHidden { updateSharingType() }

        let image = NSImage(cgImage: cgImage, size: rect.size)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        NSSound(named: "Tink")?.play()
    }

    // MARK: - Fading Ink Timer

    func startFadeTimerIfNeeded() {
        guard fadeTimer == nil,
              drawingState.strokes.contains(where: { $0.createdAt != nil }) else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.drawingState.removeExpiredStrokes()
            self.refreshCanvases()
            if !self.drawingState.strokes.contains(where: { $0.createdAt != nil }) {
                self.fadeTimer?.invalidate()
                self.fadeTimer = nil
            }
        }
    }

    // MARK: - Floating Palette

    private func showPalette() {
        let window = FloatingPaletteWindow()

        let view = FloatingPaletteView(
            drawingState: drawingState,
            overlayController: self,
            refocusCanvas: { [weak self] in
                DispatchQueue.main.async { self?.refocusCanvas() }
            }
        )

        let barSize = NSSize(width: 850, height: 42)
        let container = PaletteDragView(frame: NSRect(origin: .zero, size: barSize))
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        window.contentView = container

        if let screen = NSScreen.main {
            let x = screen.frame.midX - barSize.width / 2
            let y = screen.frame.minY + 60
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        window.setContentSize(barSize)
        window.orderFrontRegardless()
        paletteWindow = window
    }

    // MARK: - Global Hot Keys

    private func registerGlobalHotKeys() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let controller = Unmanaged<OverlayController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: controller.toggle()
                case 2: controller.appDelegate?.showPopover()
                case 3:
                    controller.drawingState.clearAll()
                    controller.refreshCanvases()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)

        registerHotKey(id: 1, keyCode: 2)    // Cmd+Shift+D
        registerHotKey(id: 2, keyCode: 35)   // Cmd+Shift+P
    }

    // Cmd+Shift+X is only claimed while there is something to clear, so other apps keep it otherwise.
    private func syncClearHotKey() {
        let wanted = withObservationTracking {
            drawingState.isActive || !drawingState.strokes.isEmpty || drawingState.boardMode != .none
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.syncClearHotKey() }
        }
        if wanted { registerHotKey(id: 3, keyCode: 7) } else { unregisterHotKey(id: 3) }
    }

    static let hotKeySignature = OSType(0x504E5354)

    private func registerHotKey(id: UInt32, keyCode: UInt32) {
        guard hotKeyRefs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: Self.hotKeySignature, id: id),
            GetApplicationEventTarget(), 0, &ref
        )
        hotKeyStatus[id] = status
        if status == noErr, let ref { hotKeyRefs[id] = ref }
    }

    private func unregisterHotKey(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        hotKeyStatus[id] = nil
    }

    deinit {
        fadeTimer?.invalidate()
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        if let colorObserver { NotificationCenter.default.removeObserver(colorObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}
