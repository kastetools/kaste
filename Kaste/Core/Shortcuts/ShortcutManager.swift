import AppKit

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    var onTogglePanel: (() -> Void)?
    var onPlainPasteCurrent: (() -> Void)?

    private var panelHotkey: Hotkey?
    private var panelPlainHotkey: Hotkey?
    private var current = (panel: Shortcut.defaultPanel, plain: Shortcut.defaultPanelPlain)
    // Raw Data blobs from UserDefaults so we can early-out on the many
    // didChangeNotification calls triggered by unrelated preference writes
    // (retention slider, maxItems stepper, autoPaste toggle, etc.) without
    // paying for a JSON decode + Shortcut equality check each time.
    private var lastPanelData: Data?
    private var lastPlainData: Data?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    func reload() {
        let panel = Shortcut.load(Shortcut.panelKey,      fallback: .defaultPanel)
        let plain = Shortcut.load(Shortcut.panelPlainKey, fallback: .defaultPanelPlain)
        rebind(panel: panel, plain: plain)
    }

    @objc private func defaultsChanged() {
        let d1 = UserDefaults.standard.data(forKey: Shortcut.panelKey)
        let d2 = UserDefaults.standard.data(forKey: Shortcut.panelPlainKey)
        if d1 == lastPanelData && d2 == lastPlainData { return }
        lastPanelData = d1
        lastPlainData = d2

        let panel = Shortcut.load(Shortcut.panelKey,      fallback: .defaultPanel)
        let plain = Shortcut.load(Shortcut.panelPlainKey, fallback: .defaultPanelPlain)
        guard panel != current.panel || plain != current.plain else { return }
        rebind(panel: panel, plain: plain)
    }

    private func rebind(panel: Shortcut, plain: Shortcut) {
        // Tear down kernel registrations explicitly BEFORE creating new ones,
        // so the old combos can't keep firing while the new ones are added.
        panelHotkey?.unregister()
        panelPlainHotkey?.unregister()
        panelHotkey = nil
        panelPlainHotkey = nil

        panelHotkey = Hotkey(keyCode: panel.keyCode,
                             modifiers: .init(rawValue: panel.mods)) { [weak self] in
            self?.onTogglePanel?()
        }
        panelPlainHotkey = Hotkey(keyCode: plain.keyCode,
                                  modifiers: .init(rawValue: plain.mods)) { [weak self] in
            self?.onPlainPasteCurrent?()
        }
        current = (panel, plain)
    }
}
