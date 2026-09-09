import AppKit
import Carbon.HIToolbox
import SwiftUI

final class OverlayController {
    let drawingState: DrawingState
    weak var appDelegate: AppDelegate?
    private(set) var overlayWindows: [OverlayWindow] = []
    private var canvasViews: [DrawingCanvasView] = []
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    private var paletteWindow: FloatingPaletteWindow?

    init(drawingState: DrawingState, appDelegate: AppDelegate) {
        self.drawingState = drawingState
        self.appDelegate = appDelegate
        registerGlobalHotKeys()
        showPalette()
    }

    // MARK: - Overlay

    func toggle() {
        if drawingState.isActive { deactivate() } else { activate() }
    }

    func activate() {
        guard !drawingState.isActive else { return }
        drawingState.isActive = true

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let canvas = DrawingCanvasView(
                frame: screen.frame,
                drawingState: drawingState,
                overlayController: self
            )
            canvas.autoresizingMask = [.width, .height]
            window.contentView = canvas
            window.ignoresMouseEvents = false
            window.sharingType = drawingState.visibleInCapture ? .readWrite : .none
            window.orderFrontRegardless()
            overlayWindows.append(window)
            canvasViews.append(canvas)
        }

        NSApp.activate(ignoringOtherApps: true)
        if let first = overlayWindows.first {
            first.makeKey()
            first.contentView?.becomeFirstResponder()
        }
    }

    func deactivate() {
        guard drawingState.isActive else { return }
        drawingState.isActive = false

        for window in overlayWindows {
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        canvasViews.removeAll()
    }

    func refreshCanvases() {
        for canvas in canvasViews {
            canvas.needsDisplay = true
        }
    }

    func refocusCanvas() {
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

    // MARK: - Floating Palette

    private func showPalette() {
        let window = FloatingPaletteWindow()

        let view = FloatingPaletteView(
            drawingState: drawingState,
            overlayController: self,
            moveWindow: { [weak window] screenPoint in
                guard let window else { return }
                window.setFrameOrigin(NSPoint(
                    x: screenPoint.x - 20,
                    y: screenPoint.y - 20
                ))
            },
            refocusCanvas: { [weak self] in
                DispatchQueue.main.async { self?.refocusCanvas() }
            }
        )

        let barSize = NSSize(width: 520, height: 42)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: barSize)
        window.contentView = hostingView

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
                default: break
                }
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)

        registerHotKey(id: 1, keyCode: 2, modifiers: UInt32(cmdKey | shiftKey))   // Cmd+Shift+D
        registerHotKey(id: 2, keyCode: 35, modifiers: UInt32(cmdKey | shiftKey))   // Cmd+Shift+P
    }

    private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x504E5354)
        hotKeyID.id = id

        var ref: EventHotKeyRef?
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            hotKeyRefs.append(ref)
        }
    }

    deinit {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
    }
}
