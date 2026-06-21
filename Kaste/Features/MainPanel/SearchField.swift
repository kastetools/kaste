import SwiftUI
import AppKit

/// Tracks whether the search field's field editor currently owns first
/// responder. Used by KeyHandler.KeyView to decide whether it's safe to
/// auto-grab focus during view-hierarchy churn (search re-filtering can
/// briefly leave window.firstResponder in a state that fools a direct
/// check). Updated via NSTextFieldDelegate begin/end editing callbacks.
enum SearchFieldFocus {
    static var isActive: Bool = false
}

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
        // Never mutate stringValue while the field editor is active — AppKit
        // can interpret that as endEditing:, drop first responder, and let
        // KeyView snipe focus during the next re-render.
        if !SearchFieldFocus.isActive && nsView.stringValue != text {
            nsView.stringValue = text
        }
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

        func controlTextDidBeginEditing(_ notification: Notification) {
            SearchFieldFocus.isActive = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            SearchFieldFocus.isActive = false
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
