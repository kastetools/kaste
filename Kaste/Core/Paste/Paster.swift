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
            pb.setString(stripMarkdown(text), forType: .string)
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
            pb.setString(stripMarkdown(text), forType: .string)
        }

        let now = Date()
        item.lastUsedAt = now
        item.useCount += 1
        // Promote to the top of the list. sortRank uses timeIntervalSince1970
        // as its base (same as newly-captured items), which is always well
        // above any rank produced by manual ⌥/⇧ reorder (~1e5–1e6 range).
        item.sortRank = now.timeIntervalSince1970

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
        guard let rawText = pb.string(forType: .string), !rawText.isEmpty else { return }
        let text = stripMarkdown(rawText)

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
        // If we inject ⌘V while the user is still physically holding ⇧ (or
        // ⌥/⌃), the OS merges our injected event with the held modifiers
        // and the target app receives ⇧⌘V instead of ⌘V — which in most
        // apps is either their own plain-paste (works accidentally) or
        // completely different (Find/Replace, no-op, …). Wait until every
        // non-cmd modifier is released, then send.
        waitForNonCommandModifiersReleased(hardDeadline: 0.8) {
            sendCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                restorePasteboard(snapshot)
            }
        }
    }

    /// Polls `NSEvent.modifierFlags` at 20ms intervals until ⇧, ⌥ and ⌃ are
    /// all released, or until `hardDeadline` seconds have elapsed. `cmd` is
    /// intentionally ignored because our injected ⌘V wants ⌘ set anyway.
    private static func waitForNonCommandModifiersReleased(
        hardDeadline: TimeInterval,
        then completion: @escaping () -> Void
    ) {
        let deadline = Date().addingTimeInterval(hardDeadline)
        func poll() {
            let mods = NSEvent.modifierFlags
            let heldNonCmd = mods.contains(.shift)
                || mods.contains(.control)
                || mods.contains(.option)
            if !heldNonCmd || Date() >= deadline {
                completion()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll() }
            }
        }
        DispatchQueue.main.async { poll() }
    }

    /// Strip markdown markup so paste-as-plain really gives the rendered
    /// text rather than the markdown source. "Plain" semantically should
    /// mean "no formatting markers of any kind", including the inline
    /// characters that happen to live inside `.string`.
    ///
    /// Two passes:
    /// - Line-level block markers (headers, lists, blockquotes, fenced
    ///   code fences) via `String` regex — AttributedString's inline-only
    ///   mode doesn't touch these.
    /// - Inline markers (bold, italic, code, link, image) via
    ///   `AttributedString(markdown:…, interpretedSyntax:
    ///   .inlineOnlyPreservingWhitespace)` so our line structure stays
    ///   intact.
    ///
    /// Content without any markdown is a no-op: regexes don't match plain
    /// prose, and AttributedString returns the text as a single run.
    static func stripMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var s = line
            // "# foo" / "## foo" / … → "foo"
            s = s.replacingOccurrences(
                of: #"^(\s*)#{1,6}[ \t]+"#, with: "$1",
                options: .regularExpression)
            // "- foo" / "* foo" / "+ foo" → "foo"
            s = s.replacingOccurrences(
                of: #"^(\s*)[-*+][ \t]+"#, with: "$1",
                options: .regularExpression)
            // "1. foo" / "12. foo" → "foo"
            s = s.replacingOccurrences(
                of: #"^(\s*)\d+\.[ \t]+"#, with: "$1",
                options: .regularExpression)
            // "> quoted" → "quoted"
            s = s.replacingOccurrences(
                of: #"^(\s*)>[ \t]?"#, with: "$1",
                options: .regularExpression)
            // Fenced code block fence lines — drop the ``` fence itself,
            // keep the content between fences intact.
            if s.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                s = ""
            }
            return s
        }
        let blockStripped = lines.joined(separator: "\n")
        guard let attr = try? AttributedString(
            markdown: blockStripped,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return blockStripped
        }
        return String(attr.characters)
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
