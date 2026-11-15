import SwiftUI
import AppKit

/// Overlay that renders a text item as discrete word chips and lets the
/// user cherry-pick which words to paste. Triggered by ⌥⏎ on any text /
/// RTF / URL card. Replaces the "copy the whole thing, re-select in the
/// target app" workflow with a one-step pick-and-go.
struct WordPickerView: View {
    let originalText: String
    /// Called with the user's chosen substring (joined by single space).
    /// Caller is expected to close the picker, close the panel, and feed
    /// the string into the source app via the normal paste pipeline.
    let onCopy: (String) -> Void
    let onCancel: () -> Void

    @State private var selectedIndices: Set<Int> = []
    @State private var tokenFrames: [Int: CGRect] = [:]
    /// Snapshot of what we're painting during a drag — true if the first
    /// word the drag touched was NOT selected (we're painting selections),
    /// false if it WAS selected (we're erasing). Nil between drags.
    @State private var dragAdditive: Bool? = nil

    private let words: [String]

    init(originalText: String,
         onCopy: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.originalText = originalText
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.words = originalText
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
    }

    var body: some View {
        ZStack {
            // Full-bleed dim + blur behind the picker so the card list
            // reads as background.
            Rectangle()
                .fill(.black.opacity(0.35))
                .background(.ultraThinMaterial)

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                content
                Divider().opacity(0.4)
                footer
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(28)
            .background(PickerKeyHandler(
                onCopySelected: copySelected,
                onCopyAll:      { onCopy(originalText) },
                onSelectAll:    { selectedIndices = Set(words.indices) },
                onClearAll:     { selectedIndices.removeAll() },
                onCancel:       onCancel
            ))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
            Text("Word Picker")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(selectedIndices.count) / \(words.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            headerButton("Select All") {
                selectedIndices = Set(words.indices)
            }
            headerButton("Clear") {
                selectedIndices.removeAll()
            }
            .disabled(selectedIndices.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func headerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.white.opacity(0.08), in: Capsule())
        .foregroundStyle(.secondary)
    }

    // MARK: - Chip grid

    @ViewBuilder
    private var content: some View {
        if words.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No words to pick")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                WordFlowLayout(spacingH: 6, spacingV: 6) {
                    ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                        wordChip(index: idx, text: word)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: "picker")
            .onPreferenceChange(TokenFramePreferenceKey.self) { tokenFrames = $0 }
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("picker"))
                    .onChanged { value in
                        let hit = tokenFrames.first { $0.value.contains(value.location) }?.key
                        guard let idx = hit else { return }
                        if dragAdditive == nil {
                            dragAdditive = !selectedIndices.contains(idx)
                        }
                        if dragAdditive == true {
                            selectedIndices.insert(idx)
                        } else {
                            selectedIndices.remove(idx)
                        }
                    }
                    .onEnded { _ in dragAdditive = nil }
            )
        }
    }

    private func wordChip(index: Int, text: String) -> some View {
        let isSelected = selectedIndices.contains(index)
        return Text(text)
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.85)
                          : Color.white.opacity(0.06))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TokenFramePreferenceKey.self,
                        value: [index: geo.frame(in: .named("picker"))]
                    )
                }
            )
            .onTapGesture { toggle(index) }
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            footerHint("Click", "Toggle")
            footerHint("Drag",  "Paint")
            footerHint("⏎",     "Copy Selected")
            footerHint("⇧⏎",   "Copy All")
            footerHint("⌘A",   "All")
            footerHint("Esc",   "Cancel")
            Spacer()
            footerAction("Cancel", prominent: false, enabled: true) {
                onCancel()
            }
            footerAction("Copy All", prominent: false, enabled: true) {
                onCopy(originalText)
            }
            footerAction("Copy \(selectedIndices.count)",
                         prominent: true,
                         enabled: !selectedIndices.isEmpty) {
                copySelected()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func footerHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func footerAction(_ title: String,
                              prominent: Bool,
                              enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent
                                 ? (enabled ? Color.white : Color.white.opacity(0.4))
                                 : .primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(
            Capsule().fill(prominent
                           ? Color.accentColor.opacity(enabled ? 0.9 : 0.35)
                           : Color.white.opacity(0.1))
        )
        .disabled(!enabled)
    }

    // MARK: - Mutations

    private func toggle(_ index: Int) {
        if selectedIndices.contains(index) { selectedIndices.remove(index) }
        else                                { selectedIndices.insert(index) }
    }

    private func copySelected() {
        guard !selectedIndices.isEmpty else { return }
        let text = selectedIndices.sorted()
            .map { words[$0] }
            .joined(separator: " ")
        onCopy(text)
    }
}

// MARK: - Helpers

private struct TokenFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Flow layout — fills left-to-right, wraps to a new row when the current
/// row can't fit the next subview. Used for the chip grid so long text
/// wraps naturally without a column constraint.
private struct WordFlowLayout: Layout {
    var spacingH: CGFloat = 6
    var spacingV: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacingV
                x = 0
                rowHeight = 0
            }
            x += size.width + spacingH
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacingH)
        }
        return CGSize(width: min(totalWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacingV
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          anchor: .topLeading,
                          proposal: .unspecified)
            x += size.width + spacingH
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Keyboard

/// Scoped first-responder view for the picker. Claims key focus on appear
/// and returns it to the card-list KeyView on disappear so the panel's
/// normal keyboard behaviour resumes cleanly.
private struct PickerKeyHandler: NSViewRepresentable {
    var onCopySelected: () -> Void
    var onCopyAll:      () -> Void
    var onSelectAll:    () -> Void
    var onClearAll:     () -> Void
    var onCancel:       () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PickerKeyView()
        view.callbacks = self
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PickerKeyView)?.callbacks = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Hand focus back to the card-list KeyView so arrow / ⏎ work again.
        if let window = nsView.window,
           let kv = KeyHandler.KeyView.activeView {
            window.makeFirstResponder(kv)
        }
    }

    final class PickerKeyView: NSView {
        var callbacks: PickerKeyHandler?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let cb = callbacks else { super.keyDown(with: event); return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 36, 76:                                // ⏎ / numpad enter
                if mods.contains(.shift) { cb.onCopyAll() }
                else                      { cb.onCopySelected() }
            case 53:                                    // esc
                cb.onCancel()
            case 0:                                     // A
                if mods.contains(.command) { cb.onSelectAll() }
                else                        { super.keyDown(with: event) }
            case 2:                                     // D
                if mods.contains(.command) { cb.onClearAll() }
                else                        { super.keyDown(with: event) }
            default:
                super.keyDown(with: event)
            }
        }
    }
}
