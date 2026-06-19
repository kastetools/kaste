import AppKit

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    var onTogglePanel: ((_ plainText: Bool) -> Void)?

    private var panelHotkey: Hotkey?
    private var panelPlainHotkey: Hotkey?
    private var current = (panel: Shortcut.defaultPanel, plain: Shortcut.defaultPanelPlain)

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
        let panel = Shortcut.load(Shortcut.panelKey,      fallback: .defaultPanel)
        let plain = Shortcut.load(Shortcut.panelPlainKey, fallback: .defaultPanelPlain)
        guard panel != current.panel || plain != current.plain else { return }
        rebind(panel: panel, plain: plain)
    }

    private func rebind(panel: Shortcut, plain: Shortcut) {
        panelHotkey = Hotkey(keyCode: panel.keyCode,
                             modifiers: .init(rawValue: panel.mods)) { [weak self] in
            self?.onTogglePanel?(false)
        }
        panelPlainHotkey = Hotkey(keyCode: plain.keyCode,
                                  modifiers: .init(rawValue: plain.mods)) { [weak self] in
            self?.onTogglePanel?(true)
        }
        current = (panel, plain)
    }
}
