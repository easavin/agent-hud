import AppKit
import SwiftUI

/// Borderless always-on-top panel that never steals focus from the terminal.
final class FloatingPanel: NSPanel {
    init<Content: View>(size: CGSize, @ViewBuilder content: () -> Content) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        let host = FirstMouseHostingView(rootView: content())
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Top-right corner of the main screen, used until the user drags it somewhere.
    func placeInDefaultCorner(margin: CGFloat = 16) {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(CGPoint(x: visible.maxX - frame.width - margin, y: visible.maxY - frame.height - margin))
    }

    /// Resizes around the top-right corner so the widget stays pinned where the user put it.
    func resize(to size: CGSize) {
        let anchor = CGPoint(x: frame.maxX, y: frame.maxY)
        setFrame(CGRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height), display: true, animate: false)
    }
}

/// The widget never becomes key, so every click is a "first mouse" click; accept them or controls feel dead.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
