import SwiftUI
import AppKit

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = IMEAwareTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onCancel = onCancel
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        (nsView as? IMEAwareTextField)?.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let tf = notification.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
    }
}

private final class IMEAwareTextField: NSTextField {
    var onCancel: (() -> Void)?

    // Only fires when the IME has NOT consumed esc (i.e., no marked text).
    // When IME is composing, AppKit sends esc to the IME first and never
    // reaches cancelOperation, so we don't break composition cancel.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
