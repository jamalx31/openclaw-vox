import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class OverlayWindowController {
    private let panel: NSPanel
    private let margin: CGFloat = 18
    private let minHeight: CGFloat = 120

    init(model: AppModel) {
        let view = OverlayView(model: model)
        let host = NSHostingController(rootView: view)

        panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentViewController = host
        (panel as? OverlayPanel)?.onEscape = { [weak model] in
            Task { @MainActor in model?.dismissOverlay() }
        }
        positionTopRight()
    }

    func show() {
        positionTopRight()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func updateHeight(contentHeight: CGFloat) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let maxHeight = visible.height * 0.45

        let desired = min(max(contentHeight, minHeight), maxHeight)
        guard abs(desired - panel.frame.height) > 1 else { return }

        var frame = panel.frame
        let oldTop = frame.origin.y + frame.size.height
        frame.size.height = desired
        frame.origin.y = oldTop - desired
        panel.setFrame(frame, display: true)
        positionTopRight()
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
