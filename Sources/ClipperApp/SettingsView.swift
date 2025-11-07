import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    @State private var availableBundleIDs: [String] = []

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                historySection
                Divider()
                    .background(Color.white.opacity(0.3))
                blacklistSection
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 40, x: 0, y: 24)
            )
        }
        .frame(width: 500, height: 520)
        .onAppear(perform: refreshBundleIDs)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)
            HStack {
                Text("Items to keep")
                Spacer()
                Text("\(settings.maxEntries)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(settings.maxEntries) },
                    set: { settings.maxEntries = Int($0.rounded()) }
                ),
                in: 1...50,
                step: 1
            )
            .labelsHidden()
            HStack {
                Text("1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("50")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var blacklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Blacklist")
                    .font(.headline)
                Spacer()
                Button("Refresh") { refreshBundleIDs() }
            }
            if availableBundleIDs.isEmpty {
                Text("No running apps detected yet.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(availableBundleIDs, id: \.self) { bundleID in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayName(for: bundleID))
                                    Text(bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle(isOn: binding(for: bundleID)) {
                                    EmptyView()
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
            }
        }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.isBlacklisted(bundleID) },
            set: { settings.setBlacklist(bundleID, isBlocked: $0) }
        )
    }

    private func refreshBundleIDs() {
        let running = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }
        let combined = Array(Set(running + settings.blacklistedBundleIDs))
        availableBundleIDs = combined.sorted()
    }

    private func displayName(for bundleID: String) -> String {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })?.localizedName {
            return running
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}
