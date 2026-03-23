import WidgetKit
import SwiftUI

@main
struct podWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentStatusWidget()
        TaskCountWidget()
        TeamActivityWidget()
    }
}
