import AppKit
import SwiftUI

@main
struct ClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore()

    init() {
        appDelegate.bootstrap(settingsStore: settingsStore)
    }

    var body: some Scene {
        Settings {
            SettingsView(settings: settingsStore, onClose: {})
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func bootstrap(settingsStore: SettingsStore) {
        let history = ClipboardHistory(settings: settingsStore)
        statusBarController = StatusBarController(history: history, settings: settingsStore)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
