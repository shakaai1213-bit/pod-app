import SwiftUI

// MARK: - Crew Tab (L2 — SPEC-POD-LAYOUT-REVAMP-2026-W22 §4)
//
// Merges Agents + Arms+Team into one tab with a segmented picker.
// "Agents" segment surfaces 4 of 5 spec sections: Focus, Agents roster, Workers, Protected Chief/Fund.
// "Arms" segment surfaces the 8 Codex arm cards (with Wake/Post) + TEAM strip.
// Tap-to-detail preserved via the existing AgentDetailSheet and arm detail flows.

struct CrewTabView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case agents
        case arms

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agents: return "Agents · Focus · Workers · Fund"
            case .arms:   return "Arms Dispatch · Team"
            }
        }

        var shortTitle: String {
            switch self {
            case .agents: return "Agents"
            case .arms:   return "Arms"
            }
        }
    }

    @State private var segment: Segment = .agents

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.top, AppTheme.spacingSM)
                .padding(.bottom, AppTheme.spacingXS)
                .background(AppColors.backgroundPrimary)

            Group {
                switch segment {
                case .agents:
                    AgentsView()
                case .arms:
                    ArmsTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.backgroundPrimary)
    }

    private var segmentPicker: some View {
        HStack(spacing: AppTheme.spacingXS) {
            ForEach(Segment.allCases) { seg in
                segmentButton(for: seg)
            }
        }
        .padding(AppTheme.spacingXS)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMedium))
    }

    private func segmentButton(for seg: Segment) -> some View {
        let isSelected = segment == seg
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
        } label: {
            Text(seg.shortTitle)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingXS + 2)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMedium)
                        .fill(isSelected ? AppColors.backgroundPrimary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.title)
    }
}

#Preview {
    CrewTabView()
        .background(AppColors.backgroundPrimary)
}
