import SwiftUI

/// Native Sonar entry point.
///
/// DirectChat remains the compatibility engine while Sonar graduates into its
/// own feature module. New Sonar-specific shell, room, evidence, and workflow
/// pieces should live under Features/Sonar and call into the shared engine only
/// where the old direct-chat behavior is still the source of truth.
typealias SonarViewModel = DirectChatViewModel

struct SonarView: View {
    @Bindable var viewModel: SonarViewModel

    var body: some View {
        DirectChatView(viewModel: viewModel)
            .background(AppColors.backgroundPrimary)
    }
}
