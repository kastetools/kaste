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
    @Query(sort: \ClipItem.sortRank, order: .reverse)
    private var allItems: [ClipItem]
    @Query(filter: #Predicate<ClipItem> { $0.isPinned },
           sort: \ClipItem.sortRank, order: .reverse)
    private var pinnedItems: [ClipItem]

    @State private var search = ""
    @State private var filter: ClipKind? = nil
    @State private var tab: Tab = .all
    @State private var listCount: Int = 0
    @State private var searchFocusTick: Int = 0

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
        .overlay {
            if let item = session.previewItem {
                PreviewOverlayView(item: item) { session.previewItem = nil }
            }
        }
        .onChange(of: session.resetTick) { _, _ in
            search = ""
            filter = nil
            tab = .all
            session.previewItem = nil
        }
        .onAppear {
            session.onSwitchTab = { forward in
                let all = Tab.allCases
                guard let idx = all.firstIndex(of: tab) else { return }
                let next = forward ? (idx + 1) % all.count : (idx - 1 + all.count) % all.count
                tab = all[next]
            }
            session.onTypedCharacter = { c in
                search.append(c)
                searchFocusTick &+= 1
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
                SearchField(text: $search,
                            placeholder: "Search",
                            focusTrigger: searchFocusTick) {
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

    let filter: ClipKind?
    let search: String
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
        self.filter = filter
        self.search = search
        self.isActive = isActive
        self._visibleCount = visibleCount

        // Descriptor only depends on `tab` so that switching filter/search does
        // NOT refetch from SwiftData — the body filters in memory instead.
        let onlyPinned = (tab == .pinned)
        let predicate = #Predicate<ClipItem> { item in
            !onlyPinned || item.isPinned
        }
        var descriptor = FetchDescriptor<ClipItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sortRank, order: .reverse)]
        )
        descriptor.fetchLimit = Self.fetchLimit
        _items = Query(descriptor)
    }

    private var displayedItems: [ClipItem] {
        let q = search.lowercased()
        let filterRaw = filter?.rawValue
        if filterRaw == nil && q.isEmpty { return items }
        return items.filter { item in
            (filterRaw == nil || item.kindRaw == filterRaw!) &&
            (q.isEmpty || (item.searchKey ?? "").contains(q))
        }
    }

    var body: some View {
        let visible = displayedItems
        return ZStack {
            cards(visible)
                .opacity(visible.isEmpty ? 0 : 1)
                .allowsHitTesting(!visible.isEmpty)
            if visible.isEmpty {
                emptyState
            }
        }
        .background {
            if isActive {
                KeyHandler(
                    onLeft: { move(-1, visible) },
                    onRight: { move(1, visible) },
                    onPrevTab: { session.onSwitchTab(false) },
                    onNextTab: { session.onSwitchTab(true) },
                    onEnter: { commit(visible) },
                    onCommandEnter: { quickLook(visible) },
                    onEsc: {
                        if session.previewItem != nil {
                            session.previewItem = nil
                        } else if selection > 0 {
                            selection = 0
                        } else {
                            onClose()
                        }
                    },
                    onSpace: { togglePreview(visible) },
                    onPin: { togglePin(visible) },
                    onDelete: { deleteAt(visible) },
                    onDigit: { jumpTo($0, visible) },
                    onTypedCharacter: { c in session.onTypedCharacter(c) },
                    digitMods: Shortcut.nsMods(from: UInt32(quickPasteModsRaw))
                )
            }
        }
        .onAppear { if isActive { visibleCount = visible.count } }
        .onChange(of: visible.count) { _, new in
            if isActive { visibleCount = new }
            if selection >= new { selection = max(0, new - 1) }
        }
        .onChange(of: isActive) { _, active in
            if active { visibleCount = visible.count }
        }
    }

    private func cards(_ visible: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 12) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                        ClipCardView(
                            item: item,
                            index: idx,
                            isSelected: idx == selection
                        )
                        .equatable()
                        .id(item.id)
                        .onTapGesture(count: 2) { selection = idx; commit(visible) }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded { selection = idx }
                        )
                        .contextMenu {
                            Button(item.isPinned ? "Unpin" : "Pin") {
                                item.isPinned.toggle()
                                try? context.save()
                            }
                            Button(plainTextMode ? "Paste as Plain Text" : "Paste") {
                                onPaste(item)
                            }
                            if item.kind == .file || item.kind == .image {
                                Divider()
                                Button("Quick Look") { ItemActions.preview(item) }
                                if item.kind == .file {
                                    Button("Open in Finder") { ItemActions.revealInFinder(item) }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                context.delete(item)
                                try? context.save()
                            }
                        }
                        .onDrag {
                            ItemActions.makeDragProvider(for: item) ?? NSItemProvider()
                        }
                        .onDrop(of: [ItemActions.internalUUIDType], isTargeted: nil) { providers in
                            handleReorderDrop(providers: providers,
                                              droppedOn: item,
                                              visible: visible)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .animation(.none, value: visible.count)
            .onChange(of: selection) { _, new in
                if new < visible.count {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(visible[new].id, anchor: .center)
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

    private func move(_ delta: Int, _ visible: [ClipItem]) {
        guard !visible.isEmpty else { return }
        selection = (selection + delta).clamped(to: 0...(visible.count - 1))
    }

    private func commit(_ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        onPaste(visible[selection])
    }

    private func quickLook(_ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        ItemActions.preview(visible[selection])
    }

    private func togglePreview(_ visible: [ClipItem]) {
        if session.previewItem != nil {
            session.previewItem = nil
        } else if visible.indices.contains(selection) {
            session.previewItem = visible[selection]
        }
    }

    private func togglePin(_ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        visible[selection].isPinned.toggle()
        try? context.save()
    }

    private func deleteAt(_ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        context.delete(visible[selection])
        try? context.save()
    }

    private func jumpTo(_ n: Int, _ visible: [ClipItem]) {
        let idx = n - 1
        guard visible.indices.contains(idx) else { return }
        selection = idx
        commit(visible)
    }

    // MARK: - Drag reorder

    /// Fires when the user drops one card on top of another (both cards live
    /// in the current panel). We move the dragged item so it sits at the
    /// same index the drop-target card currently occupies — i.e. dragging
    /// A onto B places A right where B was, pushing B one slot to the right.
    private func handleReorderDrop(providers: [NSItemProvider],
                                   droppedOn target: ClipItem,
                                   visible: [ClipItem]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(ItemActions.internalUUIDType)
        }) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: ItemActions.internalUUIDType) { data, _ in
            guard let data,
                  let text = String(data: data, encoding: .utf8),
                  let sourceID = UUID(uuidString: text),
                  sourceID != target.id else { return }
            DispatchQueue.main.async {
                reorder(sourceID: sourceID, targetID: target.id, visible: visible)
            }
        }
        return true
    }

    private func reorder(sourceID: UUID, targetID: UUID, visible: [ClipItem]) {
        guard let source = visible.first(where: { $0.id == sourceID }),
              let targetIdx = visible.firstIndex(where: { $0.id == targetID }),
              source.id != targetID else { return }

        // Insert source so that it takes over target's slot; the target and
        // everything to its right shift one position right. Compute a new
        // sortRank sitting between target and target's left neighbour.
        // Since we sort DESC by sortRank, "left" means "higher rank".
        let target = visible[targetIdx]
        let leftNeighbour = targetIdx == 0 ? nil : visible[targetIdx - 1]

        let newRank: Double
        if let left = leftNeighbour, left.id != source.id {
            newRank = (left.sortRank + target.sortRank) / 2
        } else {
            // Target is the leftmost visible card — bump above it by 1s.
            newRank = target.sortRank + 1
        }

        // Avoid rank collision if a previous reorder squashed neighbours.
        if newRank == target.sortRank || (leftNeighbour.map { newRank == $0.sortRank } ?? false) {
            renumberAllRanks(visible: visible, moving: source, before: target)
        } else {
            source.sortRank = newRank
        }

        do { try context.save() }
        catch {
            NSLog("Kaste: reorder save failed: \(error)")
            context.rollback()
        }
    }

    /// Fallback when float precision runs out between adjacent items —
    /// rewrite the whole visible sequence with fresh integer-stepped ranks,
    /// slotting the moved item into its intended position.
    private func renumberAllRanks(visible: [ClipItem], moving source: ClipItem, before target: ClipItem) {
        var order = visible.filter { $0.id != source.id }
        if let dropIdx = order.firstIndex(where: { $0.id == target.id }) {
            order.insert(source, at: dropIdx)
        } else {
            order.append(source)
        }
        // Assign large gaps so future midpoint reorders have precision.
        let step: Double = 1024
        var rank = Double(order.count) * step
        for item in order {
            item.sortRank = rank
            rank -= step
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
