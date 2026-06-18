import SwiftUI
import SwiftData

struct MenuBarContent: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ClipItem.lastUsedAt, order: .reverse)])
    private var items: [ClipItem]

    var body: some View {
        let recent = Array(items.prefix(10))
        ForEach(recent) { item in
            Button(itemTitle(item)) {
                Paster.paste(item, plainTextOnly: false)
            }
        }
        if recent.isEmpty {
            Text("No clips yet").disabled(true)
        }
        Divider()
        Button("Open Kaste  ⇧⌘V") {
            NotificationCenter.default.post(name: .kasteShowPanel, object: nil)
        }
        SettingsLink {
            Text("Preferences…")
        }
        Divider()
        Button("Quit Kaste") {
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }

    private func itemTitle(_ item: ClipItem) -> String {
        let raw = item.plainText ?? item.kind.label
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ")
        return String(oneLine.prefix(60))
    }
}

extension Notification.Name {
    static let kasteShowPanel = Notification.Name("KasteShowPanel")
}
