import SwiftUI
import AppKit

struct KeyHandler: NSViewRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void
    var onEnter: () -> Void
    var onEsc: () -> Void
    var onSpace: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    var onDigit: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.handler = self
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyView)?.handler = self
    }

    final class KeyView: NSView {
        var handler: KeyHandler?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard let h = handler else { super.keyDown(with: event); return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 123: h.onLeft()                       // ←
            case 124: h.onRight()                      // →
            case 36, 76: h.onEnter()                   // return / numpad enter
            case 53: h.onEsc()                         // esc
            case 49: h.onSpace()                       // space
            case 35:                                   // P
                if mods.contains(.command) { h.onPin() } else { super.keyDown(with: event) }
            case 51, 117: h.onDelete()                 // delete / fwd delete
            case 18...26:                              // 1..9
                if mods.contains(.command) {
                    let digit = digitForKey(event.keyCode)
                    if digit > 0 { h.onDigit(digit) }
                } else { super.keyDown(with: event) }
            default:
                super.keyDown(with: event)
            }
        }

        private func digitForKey(_ code: UInt16) -> Int {
            // 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9
            switch code {
            case 18: return 1; case 19: return 2; case 20: return 3
            case 21: return 4; case 23: return 5; case 22: return 6
            case 26: return 7; case 28: return 8; case 25: return 9
            default: return 0
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
