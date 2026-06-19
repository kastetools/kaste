import SwiftUI
import AppKit

struct ShortcutRecorderButton: View {
    @Binding var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : shortcut.displayString)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 110, minHeight: 22)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: recording ? 1.5 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(recording ? Color.accentColor.opacity(0.12) : .clear)
                        )
                )
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stop(); return nil } // esc cancels
            let carbon = Shortcut.carbonMods(from: event.modifierFlags)
            guard carbon != 0 else { NSSound.beep(); return nil }
            shortcut = Shortcut(keyCode: UInt32(event.keyCode), mods: carbon)
            stop()
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recording = false
    }
}
