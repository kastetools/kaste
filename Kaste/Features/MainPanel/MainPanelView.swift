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
            footerKey("⇧←/→", "Reorder")
            footerKey("⏎", plainTextMode ? "Paste plain" : "Paste")
            footerKey("Space", "Quick Look")
            footerKey("⌘⏎", "Reveal in Finder")
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
    @State private var dropHoverID: UUID? = nil

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
                    onMoveLeft: { moveSelected(-1, visible) },
                    onMoveRight: { moveSelected(1, visible) },
                    onEnter: { commit(visible) },
                    onCommandEnter: { revealInFinder(visible) },
                    onEsc: {
                        if selection > 0 {
                            selection = 0
                        } else {
                            onClose()
                        }
                    },
                    onSpace: { quickLook(visible) },
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
        let orderKey = visible.map(\.id)
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .center, spacing: 12) {
                    // Animate whenever the ordering (by ID) shifts — this is
                    // what makes drag / ⇧← / ⇧→ reorder slide the cards to
                    // their new slots instead of snapping.
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                        ClipCardView(
                            item: item,
                            index: idx,
                            isSelected: idx == selection
                        )
                        .equatable()
                        .overlay {
                            if dropHoverID == item.id {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                    )
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.1), value: dropHoverID == item.id)
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
                                Button("Quick Look") { QuickLookPreviewController.shared.preview(item) }
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
                        .onDrop(
                            of: [ItemActions.internalUUIDType,
                                 "public.utf8-plain-text"],
                            isTargeted: Binding(
                                get: { dropHoverID == item.id },
                                set: { targeted in
                                    if targeted {
                                        dropHoverID = item.id
                                    } else if dropHoverID == item.id {
                                        dropHoverID = nil
                                    }
                                }
                            )
                        ) { providers in
                            dropHoverID = nil
                            return handleReorderDrop(providers: providers,
                                                     droppedOn: item,
                                                     visible: visible)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                // Reorder animation: run a spring when the id-sequence
                // shifts (drag drop / ⇧+arrow / dedup). Kept off the
                // .count key path below so filter/search still snap.
                .animation(.spring(response: 0.32, dampingFraction: 0.82),
                           value: orderKey)
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
        QuickLookPreviewController.shared.preview(visible[selection])
    }

    private func revealInFinder(_ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        ItemActions.revealInFinder(visible[selection])
    }

    /// Move the currently-selected card one slot in the given direction
    /// (`delta` is -1 for left, +1 for right). Reuses the drag-drop rank
    /// math so keyboard reorder and drag reorder converge on the same
    /// sortRank strategy.
    private func moveSelected(_ delta: Int, _ visible: [ClipItem]) {
        guard visible.indices.contains(selection) else { return }
        let source = visible[selection]
        let targetIdx = selection + delta

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            // Left of index 0 or right of the last item — bump rank past the
            // extreme so the item lands at the edge without needing a
            // neighbour to interpolate with.
            if targetIdx < 0 {
                source.sortRank += 1
            } else if targetIdx >= visible.count {
                let last = visible[visible.count - 1]
                source.sortRank = last.sortRank - 1
            } else {
                let target = visible[targetIdx]
                reorder(sourceID: source.id, targetID: target.id, visible: visible)
            }
            do { try context.save() }
            catch { KLog.log("moveSelected save failed: \(error)"); context.rollback() }

            selection = max(0, min(visible.count - 1, targetIdx))
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
        KLog.log("drop: providers=\(providers.count) target=\(target.id)")
        // Try each provider in priority order — our custom UTI first, then
        // public.utf8-plain-text as a fallback for macOS versions that don't
        // route custom UTIs through SwiftUI's drop pipeline unless declared
        // in UTImportedTypeDeclarations.
        for provider in providers {
            let types = provider.registeredTypeIdentifiers
            KLog.log("drop: provider types = \(types)")
            let ourType = types.first(where: { $0 == ItemActions.internalUUIDType })
                ?? types.first(where: { $0 == "public.utf8-plain-text" })
            guard let typeIdentifier = ourType else { continue }

            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    KLog.log("drop: loadDataRepresentation error: \(error)")
                    return
                }
                guard let data,
                      let text = String(data: data, encoding: .utf8) else {
                    KLog.log("drop: empty/non-utf8 payload")
                    return
                }
                // Only act on payloads that carry our own prefix. This
                // filters out unrelated text drops that happen to hit a
                // card (e.g. dragging highlighted text from another app).
                guard text.hasPrefix(ItemActions.internalPayloadPrefix) else {
                    KLog.log("drop: payload not ours (\(text.prefix(40)))")
                    return
                }
                let uuidString = String(text.dropFirst(ItemActions.internalPayloadPrefix.count))
                guard let sourceID = UUID(uuidString: uuidString),
                      sourceID != target.id else {
                    KLog.log("drop: bad UUID or same as target")
                    return
                }
                DispatchQueue.main.async {
                    KLog.log("drop: reorder \(sourceID) → position of \(target.id)")
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        reorder(sourceID: sourceID, targetID: target.id, visible: visible)
                    }
                }
            }
            return true
        }
        KLog.log("drop: no matching provider")
        return false
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
