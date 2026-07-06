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

    /// Build the panel + SwiftUI hierarchy eagerly so the first ⇧⌘V is instant.
    /// Called once at app launch from AppDelegate.
    func warmUp() {
        _ = ensurePanel()
    }

    func toggle(plainText: Bool) {
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

        session.plainTextMode = plainText
        session.resetTick &+= 1

        state = .showing

        let target = bottomFrame()
        // If we were mid-hide, keep current y and slide back up from wherever it is.
        // Otherwise start from the off-screen position.
        if !panel.isVisible {
            var start = target
            start.origin.y -= target.height + 20
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
        }
        // Deliberately DO NOT call `NSApp.activate(ignoringOtherApps: true)`.
        // We're an accessory app with a nonactivating panel — activating the
        // whole app forcibly demotes whatever window was frontmost, which
        // shows up as a window-switch flicker under custom shortcuts like
        // ⌘⌥V. makeKeyAndOrderFront alone is enough to give the panel key
        // status without disturbing the user's app focus.
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = showDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            if self?.state == .showing { self?.state = .visible }
        })
    }

    func hide() {
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
            // don't yank the panel out from under it.
            if self?.state == .hiding {
                panel.orderOut(nil)
                panel.alphaValue = 1
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
