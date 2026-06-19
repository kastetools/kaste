import SwiftUI
import SwiftData

struct MainPanelView: View {
    @EnvironmentObject private var session: PanelSession
    @Environment(\.modelContext) private var context

    private var plainTextMode: Bool { session.plainTextMode }
    private var onPaste: (ClipItem) -> Void { session.onPaste }
    private var onClose: () -> Void { session.onClose }

    // Lightweight queries used only for tab/footer counts. SwiftData materializes
    // these as faults; the heavy blobs (.externalStorage) are not loaded.
    @Query(sort: \ClipItem.lastUsedAt, order: .reverse)
    private var allItems: [ClipItem]
    @Query(filter: #Predicate<ClipItem> { $0.isPinned },
           sort: \ClipItem.lastUsedAt, order: .reverse)
    private var pinnedItems: [ClipItem]

    @State private var search = ""
    @State private var filter: ClipKind? = nil
    @State private var tab: Tab = .all
    @State private var listCount: Int = 0
    @FocusState private var searchFocused: Bool

    enum Tab: Hashable, CaseIterable { case all, pinned }

    var body: some View {
        ZStack {
            VisualEffectBackground()
            VStack(spacing: 0) {
                ZStack {
                    header
                    tabSwitcher
                }
                Divider().opacity(0.4)
                ZStack {
                    ClipItemListView(
                        search: search,
                        filter: filter,
                        tab: .all,
                        isActive: tab == .all,
                        visibleCount: $listCount
                    )
                    .opacity(tab == .all ? 1 : 0)
                    .allowsHitTesting(tab == .all)

                    ClipItemListView(
                        search: search,
                        filter: filter,
                        tab: .pinned,
                        isActive: tab == .pinned,
                        visibleCount: $listCount
                    )
                    .opacity(tab == .pinned ? 1 : 0)
                    .allowsHitTesting(tab == .pinned)
                }
                footer
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: session.resetTick) { _, _ in
            search = ""
            filter = nil
            tab = .all
        }
        .onAppear {
            session.onSwitchTab = { forward in
                let all = Tab.allCases
                guard let idx = all.firstIndex(of: tab) else { return }
                let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
                tab = all[next]
            }
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            tabButton(.all, label: "All", count: allItems.count)
            tabButton(.pinned, label: "Pinned", count: pinnedItems.count, symbol: "pin.fill")
        }
        .padding(3)
        .background(.white.opacity(0.06), in: Capsule())
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func tabButton(_ value: Tab, label: String, count: Int, symbol: String? = nil) -> some View {
        let isOn = tab == value
        return Button { tab = value } label: {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10))
                }
                Text(label).font(.system(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.white.opacity(isOn ? 0.18 : 0.08), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(isOn ? Color.accentColor.opacity(0.28) : Color.clear, in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
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
                SearchField(text: $search, placeholder: "Search") {
                    if search.isEmpty { onClose() } else { search = "" }
                }
                .frame(width: 200, height: 18)
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
            Text("\(listCount) items")
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
}

// MARK: - List (descriptor-backed @Query)

private struct ClipItemListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: PanelSession
    @Query private var items: [ClipItem]
    @AppStorage(Shortcut.quickPasteKey) private var quickPasteModsRaw: Int = Int(Shortcut.defaultQuickPaste)

    let isActive: Bool
    @Binding var visibleCount: Int

    @State private var selection: Int = 0

    private static let fetchLimit = 500

    private var plainTextMode: Bool { session.plainTextMode }
    private var onPaste: (ClipItem) -> Void { session.onPaste }
    private var onClose: () -> Void { session.onClose }

    init(
        search: String,
        filter: ClipKind?,
        tab: MainPanelView.Tab,
        isActive: Bool,
        visibleCount: Binding<Int>
    ) {
        self.isActive = isActive
        self._visibleCount = visibleCount

        // Captured-by-macro values must be locals.
        let onlyPinned = (tab == .pinned)
        let hasFilter = (filter != nil)
        let filterRaw = filter?.rawValue ?? ""
        let hasSearch = !search.isEmpty
        let q = search.lowercased()

        let predicate = #Predicate<ClipItem> { item in
            (!onlyPinned || item.isPinned) &&
            (!hasFilter || item.kindRaw == filterRaw) &&
            (!hasSearch || (item.searchKey?.contains(q) ?? false))
        }

        var descriptor = FetchDescriptor<ClipItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.fetchLimit
        _items = Query(descriptor)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                cards
            }
        }
        .background {
            if isActive {
                KeyHandler(
                    onLeft: { move(-1) },
                    onRight: { move(1) },
                    onPrevTab: { session.onSwitchTab(false) },
                    onNextTab: { session.onSwitchTab(true) },
                    onEnter: { commitSelected() },
                    onEsc: {
                        if selection > 0 { selection = 0 } else { onClose() }
                    },
                    onSpace: {},
                    onPin: { togglePinSelected() },
                    onDelete: { deleteSelected() },
                    onDigit: { jumpTo($0) },
                    digitMods: Shortcut.nsMods(from: UInt32(quickPasteModsRaw))
                )
            }
        }
        .onAppear { if isActive { visibleCount = items.count } }
        .onChange(of: items.count) { _, new in
            if isActive { visibleCount = new }
            if selection >= new { selection = max(0, new - 1) }
        }
        .onChange(of: isActive) { _, active in
            if active { visibleCount = items.count }
        }
    }

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
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                item.isPinned.toggle()
                                try? context.save()
                            }
                            Button(plainTextMode ? "Paste as Plain Text" : "Paste") {
                                onPaste(item)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                context.delete(item)
                                try? context.save()
                            }
                        }
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
            Text("No items")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 232)
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
