import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable, Codable {
    var keyCode: UInt32
    var mods: UInt32  // Carbon modifier flags

    static let panelKey       = "shortcut.panel"
    static let panelPlainKey  = "shortcut.panelPlain"
    static let quickPasteKey  = "shortcut.quickPasteMods"

    static let defaultPanel       = Shortcut(keyCode: 9, mods: UInt32(cmdKey) | UInt32(shiftKey))
    static let defaultPanelPlain  = Shortcut(keyCode: 9, mods: UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey))
    static let defaultQuickPaste  = UInt32(cmdKey)

    static func load(_ key: String, fallback: Shortcut) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return fallback }
        return s
    }

    func save(_ key: String) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var displayString: String { Self.modsString(mods) + Self.keyLabel(keyCode) }

    static func modsString(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    static func carbonMods(from ns: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if ns.contains(.command) { m |= UInt32(cmdKey) }
        if ns.contains(.shift)   { m |= UInt32(shiftKey) }
        if ns.contains(.option)  { m |= UInt32(optionKey) }
        if ns.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    static func nsMods(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { f.insert(.command) }
        if carbon & UInt32(shiftKey)   != 0 { f.insert(.shift) }
        if carbon & UInt32(optionKey)  != 0 { f.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }

    private static let labels: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T",
        31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K",
        45:"N", 46:"M",
        18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 29:"0",
        36:"⏎", 48:"⇥", 49:"Space", 51:"⌫", 53:"Esc",
        123:"←", 124:"→", 125:"↓", 126:"↑",
        122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6",
        98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12"
    ]

    static func keyLabel(_ code: UInt32) -> String {
        labels[code] ?? "Key\(code)"
    }
}
