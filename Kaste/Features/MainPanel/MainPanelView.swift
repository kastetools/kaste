import SwiftUI
import SwiftData

struct MainPanelView: View {
    let plainTextMode: Bool
    let onPaste: (ClipItem) -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \ClipItem.lastUsedAt, order: .reverse)
    private var allItems: [ClipItem]

    @State private var search = ""
    @State private var filter: ClipKind? = nil
    @State private var selection: Int = 0
    @FocusState private var searchFocused: Bool

    private var items: [ClipItem] {
        var result = allItems.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            return a.lastUsedAt > b.lastUsedAt
        }
        if let filter { result = result.filter { $0.kind == filter } }
        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter { ($0.plainText ?? "").lowercased().contains(q) }
        }
        return result
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                if items.isEmpty {
                    emptyState
                } else {
                    cards
                }
                footer
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(KeyHandler(
            onLeft: { move(-1) },
            onRight: { move(1) },
            onEnter: { commitSelected() },
            onEsc: onClose,
            onSpace: { /* TODO quick look */ },
            onPin: { togglePinSelected() },
            onDelete: { deleteSelected() },
            onDigit: { jumpTo($0) }
        ))
        .onChange(of: items.count) { _, _ in
            if selection >= items.count { selection = max(0, items.count - 1) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundStyle(.tint)
                Text("Kaste").font(.system(size: 14, weight: .semibold))
                if plainTextMode {
                    Text("PLAIN").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.25), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 4) {
                filterChip(nil, label: "All", symbol: "tray.full")
                ForEach(ClipKind.allCases, id: \.self) { k in
                    filterChip(k, label: k.label, symbol: k.symbol)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 200)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func filterChip(_ kind: ClipKind?, label: String, symbol: String) -> some View {
        let isOn = (filter == kind)
        return Button {
            filter = kind
            selection = 0
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isOn ? Color.accentColor.opacity(0.25) : .white.opacity(0.04),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        ClipCardView(
                            item: item,
                            index: idx,
                            isSelected: idx == selection
                        )
                        .id(item.id)
                        .onTapGesture { selection = idx; commitSelected() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: selection) { _, new in
                if new < items.count {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(items[new].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Clipboard is empty")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 232)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            footerKey("←/→", "Navigate")
            footerKey("⏎", plainTextMode ? "Paste plain" : "Paste")
            footerKey("Space", "Preview")
            footerKey("⌘P", "Pin")
            footerKey("⌫", "Delete")
            footerKey("esc", "Close")
            Spacer()
            Text("\(items.count) items")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.black.opacity(0.15))
    }

    private func footerKey(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta).clamped(to: 0...(items.count - 1))
    }

    private func commitSelected() {
        guard items.indices.contains(selection) else { return }
        onPaste(items[selection])
    }

    private func togglePinSelected() {
        guard items.indices.contains(selection) else { return }
        items[selection].isPinned.toggle()
        try? context.save()
    }

    private func deleteSelected() {
        guard items.indices.contains(selection) else { return }
        context.delete(items[selection])
        try? context.save()
    }

    private func jumpTo(_ n: Int) {
        let idx = n - 1
        guard items.indices.contains(idx) else { return }
        selection = idx
        commitSelected()
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
