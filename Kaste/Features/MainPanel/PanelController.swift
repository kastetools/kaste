import AppKit
import SwiftUI
import SwiftData

@MainActor
final class PanelController: NSObject {
    private let modelContainer: ModelContainer
    private var panel: KastePanel?
    private var hosting: NSHostingView<AnyView>?
    private let session = PanelSession()
    private var previousApp: NSRunningApplication?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private let showDuration: TimeInterval = 0.24
    private let hideDuration: TimeInterval = 0.18

    private enum State { case hidden, showing, visible, hiding }
    private var state: State = .hidden
    /// Timestamp of the last user interaction. Not currently used to gate
    /// behaviour (the always-ordered-in strategy in warmUp+animateOut keeps
    /// the backing store hot regardless of idle time) but kept for logging /
    /// future diagnostics.
    private var lastActivityAt: Date = .distantPast

    /// Build the panel + SwiftUI hierarchy eagerly so the first ⇧⌘V is
    /// instant. Also parks the panel off-screen with alpha 0 while ordered
    /// in — macOS won't release its backing store while a window is in the
    /// display list, so subsequent shows are always warm regardless of how
    /// long the app has been idle. Called once at app launch.
    func warmUp() {
        let panel = ensurePanel()
        let target = bottomFrame()
        var offscreen = target
        offscreen.origin.y -= target.height + 20
        panel.setFrame(offscreen, display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        panel.displayIfNeeded()
        KLog.log("warmUp: panel at \(offscreen), isVisible=\(panel.isVisible)")
    }

    func toggle(plainText: Bool) {
        // Resync state with reality before dispatching. `hidesOnDeactivate`
        // can hide the panel behind our back when the user clicks into
        // another app — the window is gone from the screen but our state
        // is still `.visible`. Without this correction the next hotkey
        // press dispatches to hide() with a stale state, `animateOut`
        // early-returns, and its completion activates the *previous*
        // frontmost app — yanking focus away for no reason and requiring
        // a second press to actually open the panel.
        if let panel, state == .visible && !panel.isVisible {
            KLog.log("toggle: correcting stale state=.visible → .hidden (panel was hidden externally)")
            state = .hidden
        }
        KLog.log("toggle plainText=\(plainText) state=\(state)")
        switch state {
        case .hidden, .hiding:
            show(plainText: plainText)
        case .visible, .showing:
            hide()
        }
    }

    func show(plainText: Bool) {
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = ensurePanel()

        let idleFor = Date().timeIntervalSince(lastActivityAt)
        lastActivityAt = Date()
        session.plainTextMode = plainText
        session.resetTick &+= 1

        // Snapshot BEFORE flipping state so we can tell whether we're
        // starting cold (fully hidden — need to reset to off-screen so the
        // slide-up animation actually plays) or reversing a mid-hide (keep
        // current partial-alpha frame and let the animator smoothly reverse).
        let coldStart = (state == .hidden)
        state = .showing

        let target = bottomFrame()
        let visibleBefore = panel.isVisible
        let alphaBefore = panel.alphaValue
        let keyBefore = panel.isKeyWindow
        let previousAppName = previousApp?.localizedName ?? "nil"

        KLog.log("show pre: cold=\(coldStart) idle=\(Int(idleFor))s prevApp=\(previousAppName) visible=\(visibleBefore) key=\(keyBefore) alpha=\(alphaBefore) frame=\(panel.frame) target=\(target)")

        if coldStart {
            // Anchor at the off-screen start position + alpha 0. This is
            // needed both for the very first show and for shows after
            // hidesOnDeactivate hid us (which leaves frame at `target` and
            // alpha 1 — meaning without this reset the animator would run
            // from target→target and produce no visible animation).
            var start = target
            start.origin.y -= target.height + 20
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.level = .statusBar
        }

        // Aggressive front-order sequence. Any single one of these can be a
        // no-op on macOS 15+ under obscure conditions (App Nap partial wake,
        // stale spaces state, another accessory app holding key). Doing all
        // three costs nothing and covers every regression path we've hit.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.displayIfNeeded()

        // Route the initial keyboard focus to the KeyView, not the search
        // field. Even after we cleared the search text on hide, the field
        // editor from the previous session can still be first responder
        // when the hosting view is reused across shows — which then eats
        // ⌘1-9 and ← → until the user manually clicks away.
        SearchFieldFocus.isActive = false
        if let kv = KeyHandler.KeyView.activeView {
            panel.makeFirstResponder(kv)
        }

        KLog.log("show post: visible=\(panel.isVisible) key=\(panel.isKeyWindow) alpha=\(panel.alphaValue) frame=\(panel.frame) frontApp=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = showDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            if self?.state == .showing { self?.state = .visible }
            KLog.log("show done: visible=\(panel.isVisible) key=\(panel.isKeyWindow) alpha=\(panel.alphaValue) frame=\(panel.frame)")
        })
    }

    func hide() {
        lastActivityAt = Date()
        // Snapshot whether we actually had a visible panel to hide. If not,
        // this whole call is a no-op — do NOT re-activate previousApp, which
        // would steal focus from whatever the user is currently in and give
        // it to some stale record of what was frontmost during our last
        // real show().
        let wasVisible = panel?.isVisible ?? false
        animateOut { [weak self] in
            if wasVisible {
                self?.previousApp?.activate()
            } else {
                KLog.log("hide: skipping previousApp.activate (panel wasn't visible)")
            }
        }
    }

    private func commit(item: ClipItem) {
        let app = previousApp
        let plainText = session.plainTextMode
        animateOut {
            app?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                Paster.paste(item, plainTextOnly: plainText)
            }
        }
    }

    private func animateOut(_ completion: @escaping () -> Void) {
        session.previewItem = nil
        // Clear transient UI state so it doesn't linger into the next show:
        // stale search text, filter selection, tab, and any search-field
        // focus. resetTick fires an onChange listener in MainPanelView that
        // wipes @State back to defaults.
        session.resetTick &+= 1
        guard let panel, panel.isVisible else {
            state = .hidden
            completion()
            return
        }
        state = .hiding
        var off = panel.frame
        off.origin.y -= off.height + 20

        NSAnimationContext.runAnimationGroup({ [hideDuration] ctx in
            ctx.duration = hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(off, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // If a re-show happened mid-animation, state was flipped to .showing;
            // don't yank the panel out from under it. We intentionally do NOT
            // call panel.orderOut here — keeping the window in the display
            // list is what stops macOS from releasing its backing store while
            // Kaste sits idle, so the next hotkey press is always warm.
            if self?.state == .hiding {
                self?.state = .hidden
            }
            completion()
        })
    }

    private func bottomFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        let size = PanelWidth(rawValue: UserDefaults.standard.string(forKey: "panelWidth") ?? "") ?? .medium
        let width: CGFloat
        let yInset: CGFloat
        switch size {
        case .small:  width = min(frame.width - 200, 900); yInset = 24
        case .medium: width = min(frame.width - 80, 1400); yInset = 24
        case .large:  width = frame.width - 24; yInset = 12
        }
        let height: CGFloat = 332
        let x = frame.midX - width / 2
        let y = frame.minY + yInset
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func ensurePanel() -> KastePanel {
        if let panel { return panel }

        let panel = KastePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 332),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        // Deliberately false — we drive our own animated hide via the
        // didResignKey observer below. AppKit's built-in flag-hide breaks
        // the show/hide animation contract (see the observer comment).
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false

        // Wire session callbacks once; the hosting view is then reused across all show/hide.
        session.onPaste = { [weak self] item in self?.commit(item: item) }
        session.onClose = { [weak self] in self?.hide() }

        // When the user clicks into another app, run our own hide animation
        // instead of AppKit's silent flag-hide. We listen on the *app*
        // resign-active event, NOT `NSWindow.didResignKeyNotification` —
        // the latter also fires when the user opens Kaste's own Settings
        // window (which takes key from the panel while the app stays
        // active), and we do not want to hide the panel in that case.
        panel.hidesOnDeactivate = false
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.state == .visible || self.state == .showing {
                KLog.log("app resigned active while state=\(self.state); animating panel hide")
                self.hide()
            }
        }

        let root = AnyView(
            MainPanelView()
                .modelContainer(modelContainer)
                .environmentObject(session)
        )
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting

        self.panel = panel
        self.hosting = hosting
        return panel
    }

}

enum PanelWidth: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large (full width)"
        }
    }
}

final class KastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
