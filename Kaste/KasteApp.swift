import SwiftUI
import SwiftData
import AppKit

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
            NSLog("Kaste: fatal — ModelContainer failed to open: \(error)")
            container = Self.recoverOrCrash(from: error)
        }
    }

    /// Prompt the user with an actionable alert instead of dying silently. We
    /// offer "Reset" (moves the broken store aside so a fresh empty one is
    /// created), "Reveal in Finder" (so the user can back it up), or "Quit".
    private static func recoverOrCrash(from error: Error) -> ModelContainer {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Kaste can’t open its clipboard database"
        alert.informativeText = """
            The store at \(StoreManager.storeURL.path) failed to open and no backup could be restored.

            You can move the broken store aside so Kaste starts with a fresh empty history, keep your existing files intact and reveal them in Finder for manual rescue, or quit.

            Error: \(error.localizedDescription)
            """
        alert.addButton(withTitle: "Reset (fresh empty store)")
        alert.addButton(withTitle: "Reveal in Finder…")
        alert.addButton(withTitle: "Quit Kaste")

        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do {
                    return try StoreManager.resetAndMakeContainer()
                } catch {
                    NSLog("Kaste: reset also failed: \(error)")
                    // Fall through to loop; user can try Reveal or Quit.
                    alert.informativeText += "\n\nReset failed: \(error.localizedDescription)"
                }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.activateFileViewerSelecting([StoreManager.storeDirectory])
            default:
                NSApp.terminate(nil)
                // NSApp.terminate can defer; give the runloop a beat then crash
                // deliberately so we don't return an uninitialized container.
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                fatalError("Kaste terminated after container failure")
            }
        }
    }
}
