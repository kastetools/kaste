import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotkey: Hotkey?
    private var plainTextHotkey: Hotkey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.ensureSingleInstance() { return }

        NSApp.setActivationPolicy(.accessory)

        let context = AppContainer.shared.container.mainContext
        let monitor = ClipboardMonitor(context: context)
        monitor.backfillSearchKey()
        monitor.enforceRetention()
        monitor.enforceCapacity()
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

    private static func ensureSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != current.processIdentifier }
        guard let existing = others.first else { return true }

        existing.activate(options: [.activateIgnoringOtherApps])
        NSApp.terminate(nil)
        return false
    }
}
