import AppKit

enum Paster {
    /// Restores the pasteboard archive (or plain text) and synthesizes ⌘V.
    /// If Accessibility is not granted yet, copies to the pasteboard and shows
    /// our own prompt — the system prompt is never triggered automatically.
    static func paste(_ item: ClipItem, plainTextOnly: Bool) {
        let autoPaste = (UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool) ?? true
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

        // Auto-paste off → just leave content on the pasteboard.
        guard autoPaste else { return }

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
        // Defer to next runloop so we don't `runModal` synchronously inside a
        // hotkey handler or animation completion. Blocking there would stall
        // the panel hide animation and eat subsequent hotkey events.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Kaste needs Accessibility access"
            alert.informativeText = """
                The item has been copied to your clipboard, but Kaste needs Accessibility permission to auto-paste with ⏎ or ⌘1–⌘9.

                If you’ve already enabled Kaste in the list and it still doesn’t work, the system has likely cached an old code signature. Fix:

                1. Open System Settings → Privacy & Security → Accessibility
                2. Select Kaste in the list, click "–" to remove it
                3. Click "Quit Kaste" below
                4. Relaunch Kaste, then re-add it to the list (drag /Applications/Kaste.app in or hit "+")
                """
            alert.addButton(withTitle: "Open System Settings…")
            alert.addButton(withTitle: "Quit Kaste")
            alert.addButton(withTitle: "Later")
            let resp = alert.runModal()
            alertShown = false
            switch resp {
            case .alertFirstButtonReturn:
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            case .alertSecondButtonReturn:
                NSApp.terminate(nil)
            default: break
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

    /// Strip formatting from whatever is currently on the pasteboard and
    /// synthesize ⌘V into the frontmost app. No panel is shown; this is the
    /// global "plain paste" hotkey behaviour. Restores the original
    /// pasteboard contents ~350ms after the paste completes so subsequent
    /// ⌘V invocations still see the user's original formatted content.
    static func plainPasteCurrent() {
        let autoPaste = (UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool) ?? true
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        // Snapshot every type on every pasteboard item so we can restore
        // fidelity after the plain-paste completes.
        let snapshot: [[String: Data]] = (pb.pasteboardItems ?? []).map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type.rawValue] = data }
            }
            return dict
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        // Mark internal so ClipboardMonitor ignores our round-trip.
        if let first = pb.pasteboardItems?.first {
            first.setData(Data(), forType: NSPasteboard.PasteboardType("app.kaste.internal"))
        }

        guard autoPaste else { return }
        guard AXIsProcessTrusted() else {
            showAccessibilityAlert()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCommandV()
            // Give the target app 350ms to consume the plain-text paste, then
            // put the original clipboard contents back so subsequent ⌘V in
            // other apps still gets the formatted version.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                restorePasteboard(snapshot)
            }
        }
    }

    private static func restorePasteboard(_ snapshot: [[String: Data]]) {
        guard !snapshot.isEmpty else { return }
        let pb = NSPasteboard.general
        let items: [NSPasteboardItem] = snapshot.map { dict in
            let pi = NSPasteboardItem()
            for (raw, value) in dict {
                pi.setData(value, forType: NSPasteboard.PasteboardType(raw))
            }
            return pi
        }
        pb.clearContents()
        // Tag the restore too so ClipboardMonitor ignores it.
        if let first = items.first {
            first.setData(Data(), forType: NSPasteboard.PasteboardType("app.kaste.internal"))
        }
        pb.writeObjects(items)
    }
}
