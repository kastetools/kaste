import Foundation

@MainActor
final class PanelSession: ObservableObject {
    @Published var plainTextMode: Bool = false
    @Published var resetTick: Int = 0
    @Published var previewItem: ClipItem? = nil
    var onPaste: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    var onSwitchTab: (_ forward: Bool) -> Void = { _ in }
}
