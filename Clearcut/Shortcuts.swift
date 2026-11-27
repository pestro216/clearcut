import SwiftUI
import AppIntents

/// Things outside the app can ask for: a shortcut, Siri, the Action button.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var openCamera = false
}

/// "Shoot a batch": opens Clearcut's camera. Shows in the Shortcuts app and can be put on the
/// Action button or the Lock Screen.
struct ShootBatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Shoot a batch"
    static var description = IntentDescription("Opens Clearcut's camera, ready to photograph items one after another.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openCamera = true
        return .result()
    }
}

struct ClearcutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShootBatchIntent(),
                    phrases: ["Shoot a batch in \(.applicationName)", "Open the \(.applicationName) camera"],
                    shortTitle: "Shoot a batch",
                    systemImageName: "camera")
    }
}
