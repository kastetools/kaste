import AppKit
import SwiftUI
import SwiftData

@MainActor
final class PanelController: NSObject {
    private let modelContainer: ModelContainer
    private var panel: KastePanel?
    private var previousApp: NSRunningApplication?

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private let showDuration: TimeInterval = 0.24
    private let hideDuration: TimeInterval = 0.18

    func toggle(plainText: Bool) {
        if let panel, panel.isVisible {
            hide()
        } else {
            show(plainText: plainText)
        }
    }

    func show(plainText: Bool) {
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = panel ?? makePanel()
        self.panel = panel

        let onCommit: (ClipItem) -> Void = { [weak self] item in
            self?.commit(item: item, plainText: plainText)
        }
        let onClose: () -> Void = { [weak self] in self?.hide() }

        let view = MainPanelView(plainTextMode: plainText, onPaste: onCommit, onClose: onClose)
            .modelContainer(modelContainer)

        panel.contentView = NSHostingView(rootView: view)

        let target = bottomFrame()
        var start = target
        start.origin.y -= target.height + 20
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = showDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        animateOut { [weak self] in
            self?.previousApp?.activate(options: [])
        }
    }

    private func commit(item: ClipItem, plainText: Bool) {
        let app = previousApp
        animateOut {
            app?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                Paster.paste(item, plainTextOnly: plainText)
            }
        }
    }

    private func animateOut(_ completion: @escaping () -> Void) {
        guard let panel, panel.isVisible else { completion(); return }
        var off = panel.frame
        off.origin.y -= off.height + 20

        NSAnimationContext.runAnimationGroup({ [hideDuration] ctx in
            ctx.duration = hideDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(off, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
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

    private func makePanel() -> KastePanel {
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
