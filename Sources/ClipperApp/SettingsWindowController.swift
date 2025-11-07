import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        let hosting = NSHostingController(rootView: SettingsView(settings: settings) { })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        super.init(window: window)
        hosting.rootView = SettingsView(settings: settings) { [weak self] in
            self?.window?.close()
        }
        window.contentViewController = hosting
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow(relativeTo button: NSStatusBarButton?) {
        guard let window else { return }

        window.center()
        configureWindowMask()

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.orderOut(nil)
    }

    private func configureWindowMask() {
        guard let frameView = window?.contentView?.superview else { return }
        let radius: CGFloat = 24
        frameView.wantsLayer = true
        frameView.layer?.masksToBounds = true
        frameView.layer?.cornerRadius = radius
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.cornerRadius = radius
        window?.contentView?.layer?.masksToBounds = true
        window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
