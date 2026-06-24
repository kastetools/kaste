import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController?
    private var clipboardMonitor: ClipboardMonitor?
    private var snapshotTimer: Timer?
    private var napDisabler: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.ensureSingleInstance() { return }

        NSApp.setActivationPolicy(.accessory)

        // Tell macOS we must respond to the global ⇧⌘V instantly. Without
        // this, App Nap can suspend the process after long idle and the
        // first hotkey press is dropped/delayed — the user then has to press
        // it again to bring up the panel.
        napDisabler = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Kaste must respond to its global hotkey without delay"
        )

        let context = AppContainer.shared.container.mainContext
        let monitor = ClipboardMonitor(context: context)
        monitor.backfillSearchKey()
        monitor.enforceRetention()
        monitor.enforceCapacity()
        monitor.start()
        self.clipboardMonitor = monitor

        let controller = PanelController(modelContainer: AppContainer.shared.container)
        controller.warmUp()
        self.panelController = controller

        ShortcutManager.shared.onTogglePanel = { [weak controller] plain in
            controller?.toggle(plainText: plain)
        }
        ShortcutManager.shared.reload()

        // Take an online SQLite backup every 30 min so a future crash mid-write
        // can recover from a recent consistent snapshot.
        let timer = Timer.scheduledTimer(withTimeInterval: StoreManager.backupInterval,
                                         repeats: true) { _ in
            StoreManager.snapshotNow()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        snapshotTimer = timer
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let token = napDisabler {
            ProcessInfo.processInfo.endActivity(token)
            napDisabler = nil
        }
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        clipboardMonitor?.stop()
        // Capture a final snapshot on clean shutdown so the recovery path
        // has the freshest possible history if the next launch finds a
        // broken store.
        StoreManager.snapshotNow()
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
