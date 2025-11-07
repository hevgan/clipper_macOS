import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int

    init(pollingInterval: TimeInterval = 0.35) {
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { await self?.captureClipboard() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        captureClipboard()
    }

    deinit {
        timer?.invalidate()
    }

    private func captureClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let entry = ClipboardEntry(from: pasteboard) else { return }
        add(entry)
    }

    private func add(_ entry: ClipboardEntry) {
        guard entries.first?.contentIdentifier != entry.contentIdentifier else { return }
        entries.insert(entry, at: 0)
        if entries.count > 30 {
            entries.removeLast()
        }
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            pasteboard.writeObjects([image])
        }
        lastChangeCount = pasteboard.changeCount
    }

    func copyAndPaste(_ entry: ClipboardEntry) {
        copy(entry)
        sendPasteCommand()
    }

    private func sendPasteCommand() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func toggleCensor(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isCensored.toggle()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll()
    }
}

struct ClipboardEntry: Identifiable {
    enum Content {
        case text(String)
        case image(NSImage)
    }

    let id = UUID()
    let timestamp: Date
    let content: Content
    var isCensored = false

    var contentIdentifier: String {
        switch content {
        case .text(let string):
            return string
        case .image(let image):
            if let data = image.tiffRepresentation {
                return data.base64EncodedString()
            }
            return "\(image.size.width)x\(image.size.height)"
        }
    }

    init?(from pasteboard: NSPasteboard) {
        let timestamp = Date()
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            self.content = .text(text)
            self.timestamp = timestamp
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            self.content = .image(image)
            self.timestamp = timestamp
            return
        }

        return nil
    }
}

extension ClipboardEntry {
    var textPreview: String {
        guard case let .text(string) = content else {
            return ""
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 120 {
            let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 120)
            return "\(trimmed[..<endIndex])…"
        }

        return trimmed
    }

    var censoredPreview: String {
        let length = max(1, textPreview.count)
        return String(repeating: "*", count: length)
    }
}
