import OrcaDesign
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
            Group {
                if model.selectedSection == .conversations {
                    ConversationView()
                } else if model.selectedSection == .workbench {
                    EngineeringWorkbenchView()
                } else {
                    ConsoleSectionView(section: model.selectedSection)
                }
            }
            .navigationSplitViewColumnWidth(min: WorkbenchPane.minimumBarWidth, ideal: 720)
        } detail: {
            Group {
                if model.selectedSection == .conversations {
                    RuntimeInspectorView()
                } else if model.selectedSection == .workbench {
                    EngineeringWorkbenchInspectorView()
                } else {
                    ConsoleInspectorView()
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 330)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .tint(OrcaPalette.accentElectric)
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
        .background(ConsoleWindowPollingObserver(model: model))
        .onChange(of: scenePhase) { _, next in
            guard next == .active else { return }
            Task {
                if model.connectionState.isReady {
                    if model.selectedSection != .conversations { await model.refreshCurrentSurface(silent: true) }
                } else {
                    await model.connect()
                }
            }
        }
    }
}

/// Observe this Console window rather than Settings or another application's windows.
private struct ConsoleWindowPollingObserver: NSViewRepresentable {
    let model: OrcaMacModel
    func makeNSView(context: Context) -> ObserverView { ObserverView(model: model) }
    func updateNSView(_ view: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        let model: OrcaMacModel
        var tokens: [NSObjectProtocol] = []
        init(model: OrcaMacModel) { self.model = model; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            guard let window else { return }
            model.setConversationsPollingActive(NSApp.isActive && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
            for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                         NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak window] notification in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        let closing = notification.name == NSWindow.willCloseNotification && (notification.object as? NSWindow) === window
                        self.model.setConversationsPollingActive(!closing && NSApp.isActive && window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
                    }
                })
            }
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
