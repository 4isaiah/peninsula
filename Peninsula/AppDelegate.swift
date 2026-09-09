import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private(set) var drawingState = DrawingState()
    private(set) var overlayController: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayController(drawingState: drawingState, appDelegate: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Peninsula")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let view = MenuBarView(
            drawingState: drawingState,
            overlayController: overlayController,
            dismiss: { [weak self] in self?.popover.close() }
        )
        let hosting = NSHostingController(rootView: view)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
