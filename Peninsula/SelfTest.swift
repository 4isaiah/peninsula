import AppKit
import Carbon.HIToolbox

/// `Peninsula --selftest <report-file>` drives draw, undo and clear through the app's own event paths and writes a pass/fail report.
@MainActor
final class SelfTest {
    private let app: AppDelegate
    private let reportURL: URL
    private var lines: [String] = []
    private var failures = 0

    private var state: DrawingState { app.drawingState }
    private var controller: OverlayController { app.overlayController }

    static func runIfRequested(_ app: AppDelegate) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--selftest"), i + 1 < args.count else { return }
        let test = SelfTest(app: app, reportURL: URL(fileURLWithPath: args[i + 1]))
        Task { @MainActor in
            await test.run()
            NSApp.terminate(nil)
        }
    }

    private init(app: AppDelegate, reportURL: URL) {
        self.app = app
        self.reportURL = reportURL
    }

    private func run() async {
        log("binary: \(Bundle.main.executablePath ?? "?")")
        await pause(0.6)
        let front = NSWorkspace.shared.frontmostApplication
        log("frontmost before: \(front?.localizedName ?? "?")")

        check("⌘⇧D hotkey registered with the system", controller.hotKeyStatus[1] == noErr, status(1))
        check("⌘⇧X not claimed while there is nothing to clear", controller.hotKeyStatus[3] == nil)

        await fireHotKey(1)
        await pause(0.4)
        check("draw mode on", state.isActive)
        check("app is active", NSApp.isActive)
        check("overlay is key window", NSApp.keyWindow is OverlayWindow)
        check("⌘⇧X hotkey registered with the system", controller.hotKeyStatus[3] == noErr, status(3))
        check("canvas starts blank", inkPixels() == 0, "\(inkPixels()) px")

        await drawStroke(0.55)
        await drawStroke(0.70)
        check("two mouse strokes drawn", state.strokes.count == 2, "\(state.strokes.count) strokes")
        check("ink is rendered", inkPixels() > 0, "\(inkPixels()) px")

        await key(6, "z", [.command])
        check("⌘Z undoes one stroke", state.strokes.count == 1, "\(state.strokes.count) strokes")
        await key(6, "Z", [.command, .shift])
        check("⌘⇧Z redoes it", state.strokes.count == 2, "\(state.strokes.count) strokes")
        await checkpoint("ink")

        await fireHotKey(3)
        check("⌘⇧X hotkey clears all", state.strokes.isEmpty && inkPixels() == 0, summary())

        await drawStroke(0.55)
        await key(7, "X", [.command, .shift])
        check("⌘⇧X key event clears all (fallback path)", state.strokes.isEmpty && inkPixels() == 0, summary())

        await drawStroke(0.55)
        await key(51, "\u{7F}")
        check("Delete key clears all", state.strokes.isEmpty && inkPixels() == 0, summary())
        await checkpoint("cleared")

        await drawStroke(0.60)
        await key(53, "\u{1B}")
        await pause(0.5)
        check("Esc leaves draw mode", !state.isActive)
        check("ink stays on screen after leaving", controller.overlayWindows.first?.isVisible == true && inkPixels() > 0, summary())
        check("overlay is click-through", controller.overlayWindows.allSatisfy { $0.ignoresMouseEvents })
        let now = NSWorkspace.shared.frontmostApplication
        check("previous app is frontmost again", now?.processIdentifier == front?.processIdentifier && now != .current,
              now?.localizedName ?? "?")
        check("⌘⇧X still claimed while ink is on screen", controller.hotKeyStatus[3] == noErr, status(3))
        await checkpoint("exited")

        await fireHotKey(3)
        check("⌘⇧X clears leftover ink outside draw mode", state.strokes.isEmpty && inkPixels() == 0, summary())
        check("⌘⇧X released once nothing is left", controller.hotKeyStatus[3] == nil)

        log(failures == 0 ? "RESULT: ALL PASSED" : "RESULT: \(failures) FAILED")
    }

    // MARK: - Event injection

    private func key(_ keyCode: UInt16, _ chars: String, _ mods: NSEvent.ModifierFlags = []) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: mods,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: keyCode
            ) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
        await pause()
    }

    private func drawStroke(_ heightFraction: CGFloat) async {
        guard let window = controller.overlayWindows.first else { return }
        let size = window.frame.size
        let a = CGPoint(x: size.width * 0.25, y: size.height * heightFraction)
        let b = CGPoint(x: size.width * 0.75, y: size.height * (heightFraction + 0.08))
        func post(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            NSApp.postEvent(event, atStart: false)
        }
        post(.leftMouseDown, a)
        for i in 1...20 {
            let t = CGFloat(i) / 20
            post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
        post(.leftMouseUp, b)
        await pause()
    }

    private func fireHotKey(_ id: UInt32) async {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0,
                    EventAttributes(kEventAttributeNone), &event)
        var hotKeyID = EventHotKeyID(signature: OverlayController.hotKeySignature, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
        await pause()
    }

    // MARK: - Observation

    private func inkPixels() -> Int {
        guard let canvas = controller.canvasViews.first,
              let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return -1 }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let data = rep.bitmapData, rep.hasAlpha else { return -1 }
        let spp = rep.samplesPerPixel
        let alpha = rep.bitmapFormat.contains(.alphaFirst) ? 0 : spp - 1
        var count = 0
        for y in 0..<rep.pixelsHigh {
            let row = data + y * rep.bytesPerRow
            for x in 0..<rep.pixelsWide where row[x * spp + alpha] != 0 { count += 1 }
        }
        return count
    }

    private func summary() -> String { "\(state.strokes.count) strokes, \(inkPixels()) px" }

    private func status(_ id: UInt32) -> String {
        controller.hotKeyStatus[id].map { "OSStatus \($0)" } ?? "not registered"
    }

    // MARK: - Reporting

    private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        log("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
    }

    private func log(_ line: String) {
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: reportURL, atomically: true, encoding: .utf8)
    }

    /// Waits (up to 5s) for `<report>.<name>` to appear so an outside script can screenshot this state.
    private func checkpoint(_ name: String) async {
        log("CHECKPOINT \(name)")
        let ack = reportURL.path + "." + name
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: ack) { await pause(0.1) }
    }

    private func pause(_ seconds: Double = 0.3) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
