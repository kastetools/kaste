import AppKit

enum Paster {
    /// Restores the pasteboard archive (or plain text) and synthesizes ⌘V.
    /// If Accessibility is not granted yet, copies to the pasteboard and shows
    /// our own prompt — the system prompt is never triggered automatically.
    static func paste(_ item: ClipItem, plainTextOnly: Bool) {
        let trusted = AXIsProcessTrusted()
        let pb = NSPasteboard.general
        pb.clearContents()

        if plainTextOnly, let text = item.plainText {
            pb.setString(text, forType: .string)
        } else if let data = item.pasteboardArchive,
                  let dict = (try? NSKeyedUnarchiver.unarchivedObject(
                    ofClasses: [NSArray.self, NSDictionary.self, NSData.self, NSString.self],
                    from: data)) as? [[String: Data]] {
            let pbItems: [NSPasteboardItem] = dict.map { entry in
                let pi = NSPasteboardItem()
                for (raw, value) in entry {
                    pi.setData(value, forType: NSPasteboard.PasteboardType(raw))
                }
                return pi
            }
            // Mark as Kaste-internal so the monitor ignores the round-trip.
            if let first = pbItems.first {
                first.setData(Data(), forType: NSPasteboard.PasteboardType("app.kaste.internal"))
            }
            pb.writeObjects(pbItems)
        } else if let text = item.plainText {
            pb.setString(text, forType: .string)
        }

        item.lastUsedAt = Date()
        item.useCount += 1

        guard trusted else {
            showAccessibilityAlert()
            return
        }

        // Yield a tick so the previous front app regains focus, then synthesize ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            sendCommandV()
        }
    }

    private static var alertShown = false
    private static func showAccessibilityAlert() {
        guard !alertShown else { return }
        alertShown = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Kaste needs Accessibility access"
            alert.informativeText = "Kaste copied the item to your clipboard, but to auto-paste with ⏎ it needs Accessibility permission.\n\nIf you’ve granted it before, the system may have invalidated the entry after an update — toggle Kaste off and on again in the list."
            alert.addButton(withTitle: "Open System Settings…")
            alert.addButton(withTitle: "Later")
            let resp = alert.runModal()
            alertShown = false
            if resp == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
}
