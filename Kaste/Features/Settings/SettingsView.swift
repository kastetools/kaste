import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            HistoryTab().tabItem { Label("History", systemImage: "clock") }
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "command") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("panelWidth") private var panelWidth: String = PanelWidth.medium.rawValue

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Show menu bar icon", isOn: $showInMenuBar)
            Picker("Panel width", selection: $panelWidth) {
                ForEach(PanelWidth.allCases) { w in
                    Text(w.label).tag(w.rawValue)
                }
            }
            Section("Permissions") {
                Button("Open Accessibility settings…") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct HistoryTab: View {
    @AppStorage("maxItems") private var maxItems: Int = 1000
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @Environment(\.modelContext) private var context

    private static let retentionOptions: [(days: Int, label: String)] = [
        (7,  "1 week"),
        (14, "2 weeks"),
        (30, "1 month"),
        (90, "3 months")
    ]

    private var retentionIndex: Binding<Double> {
        Binding(
            get: {
                Double(Self.retentionOptions.firstIndex(where: { $0.days == retentionDays }) ?? 2)
            },
            set: { new in
                let idx = max(0, min(Self.retentionOptions.count - 1, Int(new.rounded())))
                retentionDays = Self.retentionOptions[idx].days
            }
        )
    }

    var body: some View {
        Form {
            Stepper("Keep last \(maxItems) items", value: $maxItems, in: 50...10000, step: 50)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Retention")
                    Spacer()
                    Text(Self.retentionOptions.first { $0.days == retentionDays }?.label ?? "1 month")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: retentionIndex,
                    in: 0...Double(Self.retentionOptions.count - 1),
                    step: 1
                )
                HStack {
                    ForEach(Self.retentionOptions, id: \.days) { opt in
                        Text(opt.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Button("Clear all history") {
                try? context.delete(model: ClipItem.self, where: #Predicate { !$0.isPinned })
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            LabeledContent("Toggle panel", value: "⇧⌘V")
            LabeledContent("Plain text paste", value: "⌥⇧⌘V")
            LabeledContent("Quick paste 1–9", value: "⌘1 … ⌘9")
            Text("Hotkey customization will arrive in a future build.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            Text("Kaste").font(.title2.weight(.semibold))
            Text("v0.1.0").foregroundStyle(.secondary)
            Text("Native macOS clipboard manager.")
                .font(.footnote).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
