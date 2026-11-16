import SwiftUI
import AppKit
import NaturalLanguage

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
    /// Source-text range for each `words[i]`. Preserved so copy-selected
    /// can reconstruct the original spacing (English kept as-is, adjacent
    /// Chinese words rejoined with no separator).
    private let ranges: [Range<String.Index>]

    init(originalText: String,
         onCopy: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.originalText = originalText
        self.onCopy = onCopy
        self.onCancel = onCancel
        let parsed = Self.tokenize(originalText)
        self.words  = parsed.map(\.text)
        self.ranges = parsed.map(\.range)
    }

    /// Top-level tokenizer. Two-phase:
    ///
    /// 1. **Atomic spans** — URLs, emails, phone numbers, @mentions,
    ///    Markdown links — are detected first (NSDataDetector + a couple
    ///    of regexes) and treated as a single indivisible chip. Without
    ///    this, "https://app.kolebox.id/" would collapse into
    ///    [https / app / kolebox / id] after punctuation-filtering, which
    ///    is useless for the "pick the URL" workflow.
    ///
    /// 2. **Word segmentation** — everything between (and before / after)
    ///    the atomic spans goes through Jieba (industry-standard Chinese
    ///    dictionary, also handles English), falling back to
    ///    `NLTokenizer` only if the vendored dict bundle is missing.
    private static func tokenize(
        _ text: String
    ) -> [(text: String, range: Range<String.Index>)] {
        guard !text.isEmpty else { return [] }

        let atoms = atomicSpans(in: text)
        var out: [(String, Range<String.Index>)] = []
        var cursor = text.startIndex

        for atom in atoms {
            if cursor < atom.lowerBound {
                appendWordSegmented(
                    fullText: text,
                    gap: cursor..<atom.lowerBound,
                    into: &out
                )
            }
            out.append((String(text[atom]), atom))
            cursor = atom.upperBound
        }
        if cursor < text.endIndex {
            appendWordSegmented(
                fullText: text,
                gap: cursor..<text.endIndex,
                into: &out
            )
        }
        return out
    }

    /// Discover indivisible spans — URLs, emails, phone numbers, bare
    /// email addresses, @mentions, Markdown `[text](url)` links.
    /// Overlaps are merged (longer span wins) so a URL inside a Markdown
    /// link doesn't double-register.
    private static func atomicSpans(
        in text: String
    ) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        // 1) NSDataDetector: links (incl. mailto:), phone numbers.
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            for m in detector.matches(in: text, options: [], range: full) {
                if let r = Range(m.range, in: text) { spans.append(r) }
            }
        }

        // 2) Bare email: user@host.tld (NSDataDetector's .link misses
        //    these unless prefixed with mailto:).
        let emailPattern =
            #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        appendRegexSpans(emailPattern, in: text, into: &spans)

        // 3) @mentions, supports CJK handles. `\w` in ICU regex is
        //    Unicode-aware so it covers CJK letters out of the box.
        let mentionPattern = #"@\w+"#
        appendRegexSpans(mentionPattern, in: text, into: &spans)

        // 4) Markdown links: [label](target) kept whole.
        let mdLinkPattern = #"\[[^\]\n]+\]\([^\)\n]+\)"#
        appendRegexSpans(mdLinkPattern, in: text, into: &spans)

        // Merge overlaps: sort by start, drop / extend as needed.
        spans.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for span in spans {
            if let last = merged.last, span.lowerBound < last.upperBound {
                if span.upperBound > last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<span.upperBound
                }
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    private static func appendRegexSpans(
        _ pattern: String,
        in text: String,
        into spans: inout [Range<String.Index>]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        for m in regex.matches(in: text, options: [], range: full) {
            if let r = Range(m.range, in: text) { spans.append(r) }
        }
    }

    /// Run the word segmenter on `text[gap]` and append the surviving
    /// tokens (non-whitespace, non-pure-punctuation) into `out`, with
    /// each token's range re-anchored back to the full text.
    private static func appendWordSegmented(
        fullText: String,
        gap: Range<String.Index>,
        into out: inout [(String, Range<String.Index>)]
    ) {
        let gapText = String(fullText[gap])
        let words = JiebaSegmenter.isAvailable
            ? JiebaSegmenter.rawCut(gapText)
            : nlRawTokens(gapText)
        var cursor = gap.lowerBound
        for word in words {
            guard !word.isEmpty else { continue }
            guard let found = fullText.range(
                of: word,
                options: .literal,
                range: cursor..<gap.upperBound
            ) else { continue }
            cursor = found.upperBound
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.unicodeScalars.allSatisfy({
                CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
            }) { continue }
            out.append((word, found))
        }
    }

    private static func nlRawTokens(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            out.append(String(text[range]))
            return true
        }
        return out
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
        let sorted = selectedIndices.sorted()
        var out = words[sorted[0]]
        for i in 1..<sorted.count {
            let prevIdx = sorted[i - 1]
            let currIdx = sorted[i]
            // Take the original substring sitting between the two tokens in
            // the source text; strip to whitespace only. This keeps English
            // spaces / newlines intact and lets adjacent Chinese words
            // rejoin with no inserted separator.
            let gap = originalText[ranges[prevIdx].upperBound..<ranges[currIdx].lowerBound]
            let gapWs = String(gap.filter { $0.isWhitespace })
            if !gapWs.isEmpty {
                out += gapWs + words[currIdx]
            } else {
                // No whitespace in gap → either naturally adjacent (CJK) or
                // the user skipped a non-whitespace token. Use a space only
                // when at least one side is non-CJK so Latin words don't
                // glue together.
                let bothCJK = (out.last.map(Self.isCJK) ?? false)
                           && (words[currIdx].first.map(Self.isCJK) ?? false)
                out += (bothCJK ? "" : " ") + words[currIdx]
            }
        }
        onCopy(out)
    }

    private static func isCJK(_ ch: Character) -> Bool {
        for s in ch.unicodeScalars {
            let v = s.value
            if (0x3000...0x30FF).contains(v)   // CJK symbols / Hiragana / Katakana
                || (0x3400...0x4DBF).contains(v) // CJK Unified Ext A
                || (0x4E00...0x9FFF).contains(v) // CJK Unified Ideographs
                || (0xAC00...0xD7AF).contains(v) // Hangul Syllables
                || (0xF900...0xFAFF).contains(v) // CJK Compatibility
                || (0xFF00...0xFFEF).contains(v) // Halfwidth / Fullwidth
            {
                return true
            }
        }
        return false
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
