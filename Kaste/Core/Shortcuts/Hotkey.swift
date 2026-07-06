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
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var ref: EventHotKeyRef?
    private var unregistered = false

    init(keyCode: UInt32, modifiers: Modifiers, action: @escaping () -> Void) {
        self.id = Hotkey.nextID
        Hotkey.nextID += 1

        Hotkey.installHandlerIfNeeded()
        Hotkey.actions[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B535445 /* "KSTE" */), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers.rawValue, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            self.ref = ref
            NSLog("Kaste: hotkey registered id=\(id) keyCode=\(keyCode) mods=0x\(String(modifiers.rawValue, radix: 16))")
        } else {
            Hotkey.actions[id] = nil
            NSLog("Kaste: hotkey REGISTER FAILED status=\(status) keyCode=\(keyCode) mods=0x\(String(modifiers.rawValue, radix: 16))")
        }
    }

    deinit { unregister() }

    /// Tear down the Carbon registration and clear the action.
    /// Idempotent. Call this from anywhere — don't rely on deinit timing,
    /// because the next Hotkey's RegisterEventHotKey runs *before* ARC drops
    /// the previous instance, so an old binding can linger briefly.
    func unregister() {
        guard !unregistered else { return }
        unregistered = true
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        Hotkey.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            DispatchQueue.main.async {
                // `actions` is only mutated from the main thread; reading it
                // here (after the async hop) is safe.
                if let action = Hotkey.actions[id] {
                    action()
                } else {
                    NSLog("Kaste: hotkey fired but no action for id=\(id)")
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
