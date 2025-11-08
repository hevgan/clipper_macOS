import AppKit
import SwiftUI

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? SettingsWindowController)?.close()
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private var escapeMonitor: Any?
    private lazy var panel: NSPanel = {
        let content = SettingsView(settings: settings) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingController(rootView: content)

        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        return panel
    }()

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func show(relativeTo button: NSStatusBarButton?) {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentViewController?.view)
        installEscapeMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel.orderOut(nil)
        removeEscapeMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
