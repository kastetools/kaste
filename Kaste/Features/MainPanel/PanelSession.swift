import Foundation

@MainActor
final class PanelSession: ObservableObject {
    @Published var plainTextMode: Bool = false
    @Published var resetTick: Int = 0
    var onPaste: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
}
