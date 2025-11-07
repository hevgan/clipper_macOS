import AppKit
import Foundation

final class ScreenshotWatcher {
    private let directoryURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var lastEventDate: Date
    private let handler: (URL) -> Void
    private let queue = DispatchQueue(label: "clipper.screenshotWatcher")

    init?(handler: @escaping (URL) -> Void) {
        self.handler = handler
        guard let url = ScreenshotWatcher.screenshotDirectory() else {
            return nil
        }
        directoryURL = url
        lastEventDate = Date()
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        let fileDescriptor = open(directoryURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        source?.setEventHandler { [weak self] in
            self?.scanDirectory()
        }
        source?.setCancelHandler {
            close(fileDescriptor)
        }
        source?.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func scanDirectory() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]
        var newestEvent = lastEventDate

        for url in contents where imageExtensions.contains(url.pathExtension.lowercased()) {
            guard let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]) else { continue }
            let creationDate = attributes.creationDate ?? attributes.contentModificationDate ?? Date.distantPast
            if creationDate > lastEventDate {
                newestEvent = max(newestEvent, creationDate)
                DispatchQueue.main.async { [handler] in handler(url) }
            }
        }

        lastEventDate = newestEvent
    }

    private static func screenshotDirectory() -> URL? {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (location as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }
}
