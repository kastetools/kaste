import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotkey: Hotkey?
    private var plainTextHotkey: Hotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let context = AppContainer.shared.container.mainContext
        let monitor = ClipboardMonitor(context: context)
        monitor.start()
        self.clipboardMonitor = monitor

        let controller = PanelController(modelContainer: AppContainer.shared.container)
        self.panelController = controller

        // ⇧⌘V toggles panel.
        hotkey = Hotkey(keyCode: 9, modifiers: [.command, .shift]) { [weak controller] in
            controller?.toggle(plainText: false)
        }
        // ⌥⇧⌘V toggles panel in plain-text paste mode.
        plainTextHotkey = Hotkey(keyCode: 9, modifiers: [.command, .shift, .option]) { [weak controller] in
            controller?.toggle(plainText: true)
        }

        Paster.requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
    }
}
