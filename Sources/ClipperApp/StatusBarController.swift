import AppKit
import ApplicationServices
import SwiftUI

final class StatusBarController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let statusItem: NSStatusItem
    private let history: ClipboardHistory
    private let settings: SettingsStore
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)
    private lazy var hotkeyManager = GlobalHotkeyManager { [weak self] event in
        self?.toggleWindow(for: event)
    }
    private var accessibilityManager: AccessibilityPermissionManager?
    private var windowIsVisible = false
    private var mouseDownMonitor: Any?
    private var escapeMonitor: Any?
    init(history: ClipboardHistory, settings: SettingsStore) {
        self.history = history
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let contentView = PopoverContentView(history: history)
        let hosting = NSHostingController(rootView: contentView)
        hosting.view.frame = .init(origin: .zero, size: NSSize(width: 360, height: 360))
        hosting.view.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 360)),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 280, height: 180)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.showsResizeIndicator = true
        window.contentViewController = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        super.init()

        window.delegate = self
        configureWindowMask()
        accessibilityManager = AccessibilityPermissionManager { [weak self] granted in
            self?.hotkeyManager.updatePermission(granted: granted)
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipper clipboard history")
            button.action = #selector(handleStatusItemTap(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Clipper"
        }
    }

    @objc private func handleStatusItemTap(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleWindow(for: nil)
            return
        }

        if event.type == .rightMouseUp {
            presentContextMenu(using: event)
        } else {
            toggleWindow(for: event)
        }
    }

    private func toggleWindow(for event: NSEvent?) {
        if windowIsVisible {
            closeWindow()
            return
        }

        let (anchorPoint, isStatusButton) = anchor(for: event)
        showWindow(at: anchorPoint, fromStatusItem: isStatusButton)
    }

    private func anchor(for event: NSEvent?) -> (NSPoint, Bool) {
        if let button = statusItem.button, event?.window === button.window {
            let anchor = buttonAnchorPoint(button)
            return (anchor, true)
        }

        if let event, let window = event.window {
            let point = window.convertPoint(toScreen: event.locationInWindow)
            return (point, false)
        }

        return (NSEvent.mouseLocation, false)
    }

    private func buttonAnchorPoint(_ button: NSStatusBarButton) -> NSPoint {
        guard let window = button.window else { return NSEvent.mouseLocation }
        var point = NSPoint(x: button.bounds.midX, y: button.bounds.minY)
        point = window.convertPoint(toScreen: point)
        return point
    }

    private func showWindow(at screenPoint: NSPoint, fromStatusItem: Bool) {
        let windowSize = window.frame.size
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(screenPoint, $0.frame) }) ?? NSScreen.main else {
            return
        }

        var origin = NSPoint(
            x: screenPoint.x - windowSize.width / 2,
            y: screenPoint.y - windowSize.height - (fromStatusItem ? 6 : 16)
        )
        let minX = screen.frame.minX + 12
        let maxX = screen.frame.maxX - windowSize.width - 12
        let minY = screen.frame.minY + 12
        let maxY = screen.frame.maxY - windowSize.height - 12

        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)

        window.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        configureWindowMask()
        windowIsVisible = true
        installAutoCloseMonitors()
    }

    private func closeWindow() {
        guard windowIsVisible else { return }
        windowIsVisible = false
        window.orderOut(nil)
        removeAutoCloseMonitors()
    }



    private func installAutoCloseMonitors() {
        removeAutoCloseMonitors()
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.windowIsVisible else { return }
            let cursorLocation = NSEvent.mouseLocation
            if !self.window.frame.contains(cursorLocation) {
                self.closeWindow()
            }
        }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                self.closeWindow()
            }
        }
    }

    private func removeAutoCloseMonitors() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        closeWindow()
    }

    func windowDidResignMain(_ notification: Notification) {
        closeWindow()
    }

    deinit {
        removeAutoCloseMonitors()
    }

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsItem.target = self
        let accessibilityItem = NSMenuItem(title: "Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        let quitItem = NSMenuItem(title: "Quit Clipper", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(accessibilityItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
        return menu
    }()

    private func presentContextMenu(using event: NSEvent) {
        guard let button = statusItem.button else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: button)
    }

    private func configureWindowMask() {
        guard let frameView = window.contentView?.superview else { return }
        let radius: CGFloat = 20
        frameView.wantsLayer = true
        frameView.layer?.masksToBounds = true
        frameView.layer?.cornerRadius = radius
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        if let visualEffectView = frameView.superview {
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.backgroundColor = NSColor.clear.cgColor
            visualEffectView.layer?.cornerRadius = radius
            visualEffectView.layer?.masksToBounds = true
        }
    }

    @objc private func openSettings() {
        NSLog("Opening settings window")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closeWindow()
            self.settingsWindowController.show(relativeTo: self.statusItem.button)
        }
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    @objc private func openAccessibility() {
        AccessibilityPermissionManager.openAccessibilityPreferences()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private struct PopoverContentView: View {
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        ClipboardHistoryView(history: history)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 30, x: 0, y: 15)
    }
}

final class AccessibilityPermissionManager {
    private var timer: Timer?
    private var lastTrusted: Bool
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        lastTrusted = AXIsProcessTrusted()
        onChange(lastTrusted)
        requestPermissionIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkTrust()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func requestPermissionIfNeeded() {
        guard !lastTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func checkTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != lastTrusted else { return }
        lastTrusted = trusted
        onChange(trusted)
    }

    static func openAccessibilityPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

final class GlobalHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let action: (NSEvent?) -> Void

    init(action: @escaping (NSEvent?) -> Void) {
        self.action = action
        installLocalMonitor()
    }

    deinit {
        stopMonitoring()
    }

    func updatePermission(granted: Bool) {
        if granted {
            installGlobalMonitor()
        } else {
            removeGlobalMonitor()
        }
    }

    private func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        removeGlobalMonitor()
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isHotKey(event) else { return event }
            self.action(event)
            return nil
        }
    }

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isHotKey(event) else { return }
            self.action(event)
        }
    }

    private func removeGlobalMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func isHotKey(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(), characters == "v" else {
            return false
        }
        let required: NSEvent.ModifierFlags = [.command, .shift]
        return event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: required)
    }
}
