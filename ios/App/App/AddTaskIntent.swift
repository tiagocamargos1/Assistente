import AppIntents
import UIKit

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Nova tarefa"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Tarefa")
    var taskTitle: String

    func perform() async throws -> some IntentResult {
        if let encoded = taskTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "assistentepessoal://addtask?title=\(encoded)") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

struct UrgentTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Tarefa urgente"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let fixedTitle = "Tarefa urgente"
        if let encoded = fixedTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "assistentepessoal://addtask?title=\(encoded)") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

struct AssistenteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Nova tarefa no \(.applicationName)",
                "Criar tarefa no \(.applicationName)"
            ],
            shortTitle: "Nova tarefa",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: UrgentTaskIntent(),
            phrases: [
                "Tarefa urgente no \(.applicationName)"
            ],
            shortTitle: "Tarefa urgente",
            systemImageName: "exclamationmark.triangle"
        )
    }
}
