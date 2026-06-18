import AppKit
import Carbon.HIToolbox

/// Minimal Carbon-backed global hotkey. Each instance owns one binding.
final class Hotkey {
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    private static var handlerInstalled = false
    private static var registry: [UInt32: Hotkey] = [:]
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var ref: EventHotKeyRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: Modifiers, action: @escaping () -> Void) {
        self.action = action
        self.id = Hotkey.nextID
        Hotkey.nextID += 1

        Hotkey.installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: OSType(0x4B535445 /* "KSTE" */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            self.ref = ref
            Hotkey.registry[id] = self
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Hotkey.registry[id] = nil
    }

    fileprivate func fire() { action() }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            DispatchQueue.main.async {
                Hotkey.registry[hkID.id]?.fire()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
