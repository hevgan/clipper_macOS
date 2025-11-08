import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        Group {
            if history.entries.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.entries) { entry in
                            ClipboardEntryRow(
                                entry: entry,
                                onSelect: { history.copyAndPaste(entry) },
                                onToggleCensored: { history.toggleCensor(entry) },
                                onDelete: { history.remove(entry) },
                                onCopyPath: entry.fileURL != nil ? { history.copyPath(entry) } : nil
                            )
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack {
            Text("Waiting for clipboard activity…")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let onSelect: () -> Void
    let onToggleCensored: () -> Void
    let onDelete: () -> Void
    let onCopyPath: (() -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        if let onCopyPath {
                            Button(action: onCopyPath) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        Button(action: onToggleCensored) {
                            Image(systemName: entry.isCensored ? "eye" : "eye.slash")
                        }
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.plain)
                }
                metadataRow
            }
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .text:
            let preview = entry.isCensored ? entry.censoredPreview : entry.textPreview
            Text(preview)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 140, maxHeight: 220)
                .clipped()
                .cornerRadius(10)
        }
    }

    private var metadataRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let info = entryInfoText {
                Text(info.text)
                    .font(.caption)
                    .foregroundStyle(info.color)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            Text(entry.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(alignment: .trailing)
        }
    }

    private var entryInfoText: (text: String, color: Color)? {
        if entry.wasCopied {
            return ("Copied directly to clipboard", .green)
        }
        if let fileName = entry.fileName {
            return (fileName, .secondary)
        }
        return nil
    }
}
