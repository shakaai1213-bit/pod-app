import SwiftUI

@main
struct OrcaMacApp: App {
    @State private var model = OrcaMacModel()

    var body: some Scene {
        WindowGroup("ORCA Console") {
            OrcaMacRootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .task { await model.start() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("ORCA") {
                Button("Refresh") {
                    Task {
                        if model.selectedSection == .conversations {
                            await model.refreshSelectedConversation()
                        } else {
                            await model.refreshSelectedSection()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Send") {
                    Task { await model.sendDraft() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.selectedSection != .conversations || !model.canSend)
            }
        }

        Settings {
            RuntimeSettingsView()
                .environment(model)
                .frame(width: 520)
        }
    }
}
