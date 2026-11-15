import Foundation

@MainActor
final class PanelSession: ObservableObject {
    @Published var plainTextMode: Bool = false
    @Published var resetTick: Int = 0
    /// Bumped by SearchField when the user presses Enter with non-empty
    /// search text. Active ClipItemListView observes and jumps selection
    /// to 0 + hands keyboard focus back to KeyHandler.
    @Published var searchSubmitTick: Int = 0
    /// Non-nil while the Word Picker overlay is on top of the card list.
    /// MainPanelView renders the picker whenever this is set; the active
    /// ClipItemListView drops keyboard focus so the picker's own key view
    /// can take over.
    @Published var pickerItem: ClipItem? = nil
    var onPaste: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSwitchTab: (_ forward: Bool) -> Void = { _ in }
    var onTypedCharacter: (_ chars: String) -> Void = { _ in }
    /// Paste an arbitrary string (used by Word Picker — the string isn't
    /// tied to any single ClipItem). Writes `.string` to the pasteboard,
    /// closes the panel, and synthesizes ⌘V into the previous frontmost
    /// app, same lifecycle as a normal item commit.
    var onPasteRawText: (String) -> Void = { _ in }
}
