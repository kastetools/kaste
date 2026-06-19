import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class PreviewController {
    private let session: PanelSession
    private let modelContainer: ModelContainer
    private var panel: PreviewPanel?
    private var sink: AnyCancellable?

    init(session: PanelSession, modelContainer: ModelContainer) {
        self.session = session
        self.modelContainer = modelContainer
        sink = session.$previewItem
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                if let item { self?.show(item: item) } else { self?.hide() }
            }
    }

    private func ensurePanel() -> PreviewPanel {
        if let panel { return panel }

        let panel = PreviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        let root = AnyView(
            PreviewWindowView()
                .modelContainer(modelContainer)
                .environmentObject(session)
        )
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        return panel
    }

    private func show(item: ClipItem) {
        let panel = ensurePanel()
        panel.setFrame(targetFrame(), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let vf = screen.visibleFrame
        // Main panel sits at the bottom (~24pt inset + 332 height). Place preview above.
        let mainPanelTop = vf.minY + 24 + 332
        let gap: CGFloat = 24

        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 720
        let width = min(vf.width - 120, maxWidth)
        let availableHeight = vf.maxY - mainPanelTop - gap - 24
        let height = min(availableHeight, maxHeight)

        let x = vf.midX - width / 2
        let y = mainPanelTop + gap + (availableHeight - height) / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PreviewWindowView: View {
    @EnvironmentObject var session: PanelSession

    var body: some View {
        if let item = session.previewItem {
            PreviewOverlayView(item: item) { session.previewItem = nil }
        } else {
            Color.clear
        }
    }
}
