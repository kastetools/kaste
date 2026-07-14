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
        state = .showing

        let target = bottomFrame()
        let visibleBefore = panel.isVisible
        let alphaBefore = panel.alphaValue
        let keyBefore = panel.isKeyWindow
        let previousAppName = previousApp?.localizedName ?? "nil"

        KLog.log("show pre: idle=\(Int(idleFor))s prevApp=\(previousAppName) visible=\(visibleBefore) key=\(keyBefore) alpha=\(alphaBefore) frame=\(panel.frame) target=\(target)")

        // Emergency fallback: if somehow the panel got orderOut'd elsewhere,
        // re-anchor at the off-screen position before ordering back in.
        if !panel.isVisible {
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
        animateOut { [weak self] in
            self?.previousApp?.activate()
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
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false

        // Wire session callbacks once; the hosting view is then reused across all show/hide.
        session.onPaste = { [weak self] item in self?.commit(item: item) }
        session.onClose = { [weak self] in self?.hide() }

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
