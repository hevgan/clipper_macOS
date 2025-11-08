import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let settings: SettingsStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var settingsObservation: AnyCancellable?
    private var screenshotWatcher: ScreenshotWatcher?

    init(settings: SettingsStore, pollingInterval: TimeInterval = 0.35) {
        self.settings = settings
        let pasteboard = NSPasteboard.general
        lastChangeCount = pasteboard.changeCount
        timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { await self?.captureClipboard() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        settingsObservation = settings.$maxEntries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.enforceLimit()
            }
        screenshotWatcher = ScreenshotWatcher { [weak self] url in
            Task { @MainActor [weak self] in
                self?.addScreenshot(from: url)
            }
        }
        captureClipboard()
    }

    deinit {
        timer?.invalidate()
        settingsObservation?.cancel()
    }

    private func captureClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard shouldCaptureFromCurrentApp() else { return }
        guard let entry = ClipboardEntry(from: pasteboard) else { return }
        add(entry)
    }

    private func shouldCaptureFromCurrentApp() -> Bool {
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return !settings.isBlacklisted(bundleIdentifier)
    }

    private func add(_ entry: ClipboardEntry) {
        guard entries.first?.contentIdentifier != entry.contentIdentifier else { return }
        entries.insert(entry, at: 0)
        enforceLimit()
    }

    private func addScreenshot(from url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let entry = ClipboardEntry(image: image, fileURL: url, fileName: url.lastPathComponent, wasCopied: false)
        add(entry)
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
        case .image(let image):
            if let url = entry.fileURL {
                pasteboard.writeObjects([url as NSURL])
            } else {
                pasteboard.writeObjects([image])
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    func copyPathAndPaste(_ entry: ClipboardEntry) {
        guard let url = entry.fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        lastChangeCount = pasteboard.changeCount
        sendPasteCommand()
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

    private func enforceLimit() {
        let limit = settings.maxEntries
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
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
    let fileURL: URL?
    let fileName: String?
    var wasCopied: Bool
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
        if let imageResult = Self.imageFromPasteboard(pasteboard) ?? NSImage(pasteboard: pasteboard).map({ (image: $0, url: nil, fileName: nil) }) {
            self.content = .image(imageResult.image)
            self.fileURL = imageResult.url
            self.fileName = imageResult.fileName ?? imageResult.url?.lastPathComponent
            self.timestamp = timestamp
            self.wasCopied = imageResult.url == nil
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            self.content = .text(text)
            self.fileURL = nil
            self.fileName = nil
            self.timestamp = timestamp
            self.wasCopied = true
            return
        }

        self.fileName = nil
        self.fileURL = nil
        self.wasCopied = false

        return nil
    }

    init(image: NSImage, fileURL: URL?, fileName: String?, wasCopied: Bool = false) {
        self.content = .image(image)
        self.fileURL = fileURL
        self.fileName = fileName
        self.timestamp = Date()
        self.isCensored = false
        self.wasCopied = wasCopied
    }

    private static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> (image: NSImage, url: URL?, fileName: String?)? {
        if let fileBased = imageFromFileEntries(pasteboard) {
            return fileBased
        }

        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.jpeg-2000"),
            NSPasteboard.PasteboardType("com.apple.screencapture.image")
        ]

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first {
            return (image: image, url: nil, fileName: nil)
        }

        for item in pasteboard.pasteboardItems ?? [] {
            if let type = item.availableType(from: preferredTypes),
               let data = item.data(forType: type),
               let image = NSImage(data: data) {
                return (image: image, url: nil, fileName: nil)
            }

            if let promisedList = item.propertyList(forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url-list")) as? [String] {
                for path in promisedList {
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    if let image = NSImage(contentsOf: url) {
                        return (image: image, url: url, fileName: url.lastPathComponent)
                    }
                }
            }

            if let pdfData = item.data(forType: .pdf), let pdfImage = NSImage(data: pdfData) {
                return (image: pdfImage, url: nil, fileName: nil)
            }
        }

        if let legacyPaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in legacyPaths {
                let url = URL(fileURLWithPath: path)
                if let image = NSImage(contentsOf: url) {
                    return (image: image, url: url, fileName: url.lastPathComponent)
                }
            }
        }

        return nil
    }

    private static func imageFromFileEntries(_ pasteboard: NSPasteboard) -> (image: NSImage, url: URL?, fileName: String?)? {
        for item in pasteboard.pasteboardItems ?? [] {
            if let result = imageFromFileItem(item) {
                return result
            }
        }
        return nil
    }

    private static func imageFromFileItem(_ item: NSPasteboardItem) -> (image: NSImage, url: URL?, fileName: String?)? {
        if let fileURLString = item.string(forType: .fileURL) {
            let url = URL(string: fileURLString)?.absoluteURL ?? URL(fileURLWithPath: fileURLString)
            if url.isFileURL, let image = NSImage(contentsOf: url) {
                return (image: image, url: url, fileName: url.lastPathComponent)
            }
        }

        if let plainText = item.string(forType: .string),
           let candidateURL = urlFromPathString(plainText),
           let image = NSImage(contentsOf: candidateURL) {
            return (image: image, url: candidateURL, fileName: candidateURL.lastPathComponent)
        }

        return nil
    }

    private static func urlFromPathString(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
        return nil
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
}

extension ClipboardEntry {
    var textPreview: String {
        guard case let .text(string) = content else {
            return ""
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    var censoredPreview: String {
        let length = max(1, textPreview.count)
        return String(repeating: "*", count: length)
    }
}
