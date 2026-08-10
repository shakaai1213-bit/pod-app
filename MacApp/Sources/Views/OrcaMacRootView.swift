import SwiftUI

struct OrcaMacRootView: View {
    @Environment(OrcaMacModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AgentSidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } content: {
            ConversationView()
                .navigationSplitViewColumnWidth(min: 520, ideal: 720)
        } detail: {
            RuntimeInspectorView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 330)
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "ORCA",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK") { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "Unknown error")
        }
        .onChange(of: scenePhase) { _, next in
            guard next == .active else { return }
            Task {
                if model.connectionState.isReady {
                    await model.refreshSelectedConversation(silent: true)
                } else {
                    await model.connect()
                }
            }
        }
    }
}
