import SwiftUI
import SwiftData

@main
struct KasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kaste", systemImage: "doc.on.clipboard.fill") {
            MenuBarContent()
                .modelContainer(AppContainer.shared.container)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .modelContainer(AppContainer.shared.container)
        }
    }
}

final class AppContainer {
    static let shared = AppContainer()
    let container: ModelContainer

    private init() {
        do {
            container = try StoreManager.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
