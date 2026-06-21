import SwiftUI
import AppKit

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusTrigger: Int = 0
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

        if focusTrigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                window.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView {
                    editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var lastFocusTrigger: Int = 0
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
        // First Esc on a focused search field → just blur and hand keyboard
        // focus back to KeyHandler so ⌘1-9 / arrows / ⏎ work again. A second
        // Esc (now on KeyHandler) runs the normal close logic.
        if let target = KeyHandler.KeyView.activeView,
           let window = self.window {
            window.makeFirstResponder(target)
        } else {
            onCancel?()
        }
    }
}
