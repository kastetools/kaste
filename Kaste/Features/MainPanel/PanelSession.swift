import Foundation

@MainActor
final class PanelSession: ObservableObject {
    @Published var plainTextMode: Bool = false
    @Published var resetTick: Int = 0
    /// Bumped by SearchField when the user presses Enter with non-empty
    /// search text. Active ClipItemListView observes and jumps selection
    /// to 0 + hands keyboard focus back to KeyHandler.
    @Published var searchSubmitTick: Int = 0
    var onPaste: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSwitchTab: (_ forward: Bool) -> Void = { _ in }
    var onTypedCharacter: (_ chars: String) -> Void = { _ in }
}
