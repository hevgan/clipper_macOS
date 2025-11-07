import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var maxEntries: Int {
        didSet {
            let clamped = Self.clamp(maxEntries)
            if clamped != maxEntries {
                maxEntries = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.maxEntries)
        }
    }

    @Published private(set) var blacklistedBundleIDs: [String] {
        didSet {
            defaults.set(blacklistedBundleIDs, forKey: Keys.blacklist)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedMax = defaults.object(forKey: Keys.maxEntries) as? Int
        let initialMax = savedMax ?? 30
        self.maxEntries = Self.clamp(initialMax)
        let savedBlacklist = defaults.stringArray(forKey: Keys.blacklist) ?? []
        self.blacklistedBundleIDs = savedBlacklist
    }

    private static func clamp(_ value: Int) -> Int {
        return min(max(value, 1), 50)
    }

    func addToBlacklist(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !blacklistedBundleIDs.contains(trimmed) else { return }
        blacklistedBundleIDs.insert(trimmed, at: 0)
    }

    func removeFromBlacklist(_ bundleID: String) {
        blacklistedBundleIDs.removeAll { $0 == bundleID }
    }

    func setBlacklist(_ bundleID: String, isBlocked: Bool) {
        if isBlocked {
            addToBlacklist(bundleID)
        } else {
            removeFromBlacklist(bundleID)
        }
    }

    func isBlacklisted(_ bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return blacklistedBundleIDs.contains(id)
    }

    private enum Keys {
        static let maxEntries = "settings.maxEntries"
        static let blacklist = "settings.blacklistedBundleIDs"
    }
}
