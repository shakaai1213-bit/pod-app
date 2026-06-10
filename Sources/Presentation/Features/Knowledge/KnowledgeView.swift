import SwiftUI
import UIKit

// MARK: - Knowledge Chip (L4 — SPEC-POD-LAYOUT-REVAMP-2026-W22 §5)

enum KnowledgeChip: String, CaseIterable, Identifiable {
    case memory
    case doctrine
    case wiki
    case review
    case notes
    case skills
    case standards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory:    return "Memory"
        case .doctrine:  return "Doctrine"
        case .wiki:      return "Wiki"
        case .review:    return "Review"
        case .notes:     return "Notes"
        case .skills:    return "Skills"
        case .standards: return "Standards"
        }
    }

    var icon: String {
        switch self {
        case .memory:    return "brain.head.profile"
        case .doctrine:  return "square.stack.3d.up"
        case .wiki:      return "doc.richtext"
        case .review:    return "tray.full"
        case .notes:     return "note.text"
        case .skills:    return "wand.and.stars"
        case .standards: return "books.vertical"
        }
    }
}

// MARK: - Knowledge View

struct KnowledgeView: View {

    @EnvironmentObject private var appState: AppState
    @State private var viewModel = KnowledgeViewModel()
    @State private var showingEditor = false
    @State private var editingStandard: Standard?
    @State private var selectedStandard: Standard?
    @State private var selectedNote: OrcaNote?
    @State private var selectedSkillLabSkill: SkillLabSkill?
    @State private var noteFilter: OrcaNoteFilter = .all
    @State private var newSystemNoteTitle = ""
    @State private var newSystemNoteBody = ""
    @State private var newSystemNoteType = "decision"
    @State private var isSavingSystemNote = false
    @State private var systemNoteStatus: String?
    @State private var searchText = ""
    @State private var knowledgeSearchTask: Task<Void, Never>?
    @State private var selectedChip: KnowledgeChip = .memory

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // L4: chip-nav bar
                    knowledgeChipBar
                        .padding(.horizontal, Theme.md)
                        .padding(.top, Theme.xs)
                        .padding(.bottom, Theme.xs)
                        .background(AppColors.backgroundPrimary)

                    ScrollView {
                        VStack(spacing: Theme.lg) {
                            searchBar
                            knowledgePacketSearchSection
                            knowledgeChipContent
                        }
                        .padding(.horizontal, Theme.md)
                        .padding(.bottom, 100)
                    }
                    .background(AppColors.backgroundPrimary)
                    .refreshable {
                        await viewModel.loadStandards()
                        await viewModel.loadWikiContext()
                        await viewModel.loadWikiDocuments()
                        await viewModel.loadDoctrineBundles()
                        await viewModel.loadDocRegistry()
                        await viewModel.loadNotes()
                        await viewModel.loadReviewQueue()
                        await viewModel.loadRuntimeReviewQueue()
                        await viewModel.loadReviewSyncPreview()
                        await viewModel.loadRuntimeSyncPreview()
                        await viewModel.loadMemoryCandidates()
                        await viewModel.loadSkillLab()
                    }
                }

                // FAB
                fabButton
            }
            .navigationTitle("Knowledge")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppColors.backgroundPrimary, for: .navigationBar)
            .navigationDestination(item: $selectedStandard) { standard in
                StandardDetailView(standard: standard, viewModel: viewModel)
            }
            .sheet(isPresented: $showingEditor) {
                StandardEditorView(
                    mode: .create,
                    viewModel: viewModel
                )
            }
            .sheet(item: $editingStandard) { standard in
                StandardEditorView(
                    mode: .edit(standard),
                    viewModel: viewModel
                )
            }
            .sheet(item: $selectedNote) { note in
                OrcaNoteDetailSheet(note: note)
            }
            .sheet(item: $selectedSkillLabSkill) { skill in
                SkillLabDetailSheet(
                    skill: skill,
                    detail: viewModel.selectedSkillLabDetail,
                    isLoading: viewModel.isLoadingSkillLabDetail,
                    errorMessage: viewModel.skillLabDetailErrorMessage
                )
            }
            .sheet(item: $viewModel.selectedWikiDocument) { document in
                WikiDocumentMirrorSheet(
                    document: document,
                    isLoading: viewModel.isLoadingSelectedWikiDocument,
                    errorMessage: viewModel.wikiDocumentsErrorMessage
                )
            }
            .sheet(item: $viewModel.selectedKnowledgePacket) { packet in
                KnowledgePacketDetailSheet(packet: packet)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                configureReviewerIdentity()
                consumePendingKnowledgeIntent()
            }
            .onChange(of: appState.currentUser?.name) { _, _ in
                configureReviewerIdentity()
            }
            .task {
                configureReviewerIdentity()
                consumePendingKnowledgeIntent()
                await viewModel.loadStandards()
                await viewModel.loadWikiContext()
                await viewModel.loadWikiDocuments()
                await viewModel.loadDoctrineBundles()
                await viewModel.loadDocRegistry()
                await viewModel.loadNotes()
                await viewModel.loadReviewQueue()
                await viewModel.loadRuntimeReviewQueue()
                await viewModel.loadReviewSyncPreview()
                await viewModel.loadRuntimeSyncPreview()
                await viewModel.loadMemoryCandidates()
                await viewModel.loadSkillLab()
            }
        }
    }

    private func configureReviewerIdentity() {
        viewModel.configureReviewerIdentity(from: appState.currentUser?.name ?? appState.authManager.currentUser?.name)
    }

    private func consumePendingKnowledgeIntent() {
        if let rawChip = UserDefaults.standard.string(forKey: "pod.pendingKnowledgeChip"),
           let chip = KnowledgeChip(rawValue: rawChip) {
            selectedChip = chip
            UserDefaults.standard.removeObject(forKey: "pod.pendingKnowledgeChip")
        }
        if UserDefaults.standard.string(forKey: "pod.pendingMemoryCandidateId") != nil {
            selectedChip = .memory
            UserDefaults.standard.removeObject(forKey: "pod.pendingMemoryCandidateId")
        }
    }

    // MARK: - Chip Nav (L4)

    private var knowledgeChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.xs) {
                ForEach(KnowledgeChip.allCases) { chip in
                    knowledgeChipButton(for: chip)
                }
            }
        }
    }

    private func knowledgeChipButton(for chip: KnowledgeChip) -> some View {
        let isSelected = selectedChip == chip
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedChip = chip }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chip.icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                Text(chip.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? AppColors.accentElectric : AppColors.textSecondary)
            .padding(.horizontal, Theme.sm)
            .padding(.vertical, Theme.xs + 1)
            .background(
                Capsule()
                    .fill(isSelected ? AppColors.backgroundSecondary : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppColors.accentElectric.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.title)
    }

    @ViewBuilder
    private var knowledgeChipContent: some View {
        switch selectedChip {
        case .memory:
            memoryCandidatesSection

        case .doctrine:
            doctrineBundlesSection
            docRegistrySection

        case .wiki:
            chronogramSection
            wikiMirrorSection

        case .review:
            reviewQueueSection

        case .notes:
            notesAndDecisionsSection

        case .skills:
            skillLabSection

        case .standards:
            categoryGrid
            if !viewModel.recentStandards.isEmpty {
                recentSection
            }
            if !viewModel.favoriteStandards.isEmpty {
                favoritesSection
            }
            standardsList
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textTertiary)

            TextField("Ask what the team has already learned.", text: $searchText)
                .font(.subheadline)
                .foregroundColor(AppColors.textPrimary)
                .tint(AppColors.accentElectric)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    knowledgeSearchTask?.cancel()
                    viewModel.knowledgePacketQueryText = searchText
                    Task { await viewModel.searchKnowledgePackets() }
                }
                .onChange(of: searchText) { _, newValue in
                    viewModel.searchText = newValue
                    viewModel.knowledgePacketQueryText = newValue
                    knowledgeSearchTask?.cancel()
                    knowledgeSearchTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if Task.isCancelled { return }
                        await viewModel.searchKnowledgePackets()
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.searchText = ""
                    viewModel.knowledgePacketQueryText = ""
                    knowledgeSearchTask?.cancel()
                    Task { await viewModel.searchKnowledgePackets() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.sm)
        .padding(.vertical, Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var knowledgePacketSearchSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Knowledge Search", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if viewModel.isLoadingKnowledgePackets {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !viewModel.knowledgePacketResults.isEmpty {
                    Text("\(viewModel.knowledgePacketResults.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(Capsule())
                }
            }

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Ask what the team has already learned.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            } else if let error = viewModel.knowledgePacketErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.accentWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if viewModel.knowledgePacketResults.isEmpty && !viewModel.isLoadingKnowledgePackets {
                Text("No knowledge packets matched this search.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else {
                LazyVStack(spacing: Theme.xs) {
                    ForEach(viewModel.knowledgePacketResults.prefix(10)) { packet in
                        KnowledgePacketResultRow(packet: packet) {
                            viewModel.selectedKnowledgePacket = packet
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
        }
    }

    private var chronogramSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Chronogram", systemImage: "clock.badge.checkmark")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadWikiContext()
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingWiki ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingWiki)
                .accessibilityLabel("Refresh chronogram")
            }

            if viewModel.isLoadingWiki && viewModel.todayChronogram == nil {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading Team-Wiki...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if let doc = viewModel.todayChronogram {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(spacing: Theme.xs) {
                        Text(doc.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(doc.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Text(doc.path)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)

                    Text(Self.chronogramPreview(doc.content))
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.wikiErrorMessage ?? "Team-Wiki is unavailable from ORCA.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private static func chronogramPreview(_ content: String?) -> String {
        let lines = (content ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && trimmed != "---" && !trimmed.hasPrefix("title:") && !trimmed.hasPrefix("status:") && !trimmed.hasPrefix("owner:") && !trimmed.hasPrefix("date:")
        }
        return lines.prefix(12).joined(separator: "\n")
    }

    private var wikiMirrorSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Wiki Mirror", systemImage: "doc.richtext")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadWikiDocuments(query: searchText)
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingWikiDocuments ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingWikiDocuments)
                .accessibilityLabel("Refresh wiki mirror")
            }

            if viewModel.isLoadingWikiDocuments && viewModel.wikiDocuments.isEmpty {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Mirroring Team-Wiki from ORCA...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if !viewModel.wikiDocuments.isEmpty {
                LazyVStack(spacing: Theme.xs) {
                    ForEach(viewModel.wikiDocuments.prefix(12)) { doc in
                        WikiMirrorRow(document: doc) {
                            Task {
                                await viewModel.openWikiDocument(doc)
                            }
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.wikiDocumentsErrorMessage ?? "No Team-Wiki documents mirrored yet.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var docRegistrySection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Doc Registry", systemImage: "books.vertical")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadDocRegistry()
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingDocRegistry ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingDocRegistry)
                .accessibilityLabel("Refresh document registry")
            }

            if viewModel.isLoadingDocRegistry && viewModel.docRegistrySummary == nil {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Scanning ORCA docs...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if let summary = viewModel.docRegistrySummary {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        RegistryStat(value: summary.total, label: "docs")
                        RegistryStat(value: summary.requiredCount ?? 0, label: "required")
                        RegistryStat(value: summary.byDoctrineStatus?["canonical"] ?? 0, label: "canonical")
                        RegistryStat(value: summary.byChromaStatus["unknown"] ?? 0, label: "index ?")
                    }

                    LazyVStack(spacing: Theme.xs) {
                        ForEach(viewModel.docRegistryItems.prefix(10)) { item in
                            RegistryDocRow(item: item)
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.docRegistryErrorMessage ?? "Doc Registry is unavailable from ORCA.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var doctrineBundlesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Doctrine Bundles", systemImage: "square.stack.3d.up")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadDoctrineBundles()
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingDoctrineBundles ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingDoctrineBundles)
                .accessibilityLabel("Refresh doctrine bundles")
            }

            if viewModel.isLoadingDoctrineBundles && viewModel.doctrineBundles.isEmpty {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading doctrine bundles...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if !viewModel.doctrineBundles.isEmpty {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    LazyVStack(spacing: Theme.xs) {
                        ForEach(viewModel.doctrineBundles) { bundle in
                            Button {
                                Task {
                                    await viewModel.loadDoctrineBundle(id: bundle.id)
                                }
                            } label: {
                                DoctrineBundleRow(
                                    bundle: bundle,
                                    isSelected: viewModel.selectedDoctrineBundle?.id == bundle.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let detail = viewModel.selectedDoctrineBundle {
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack(spacing: Theme.sm) {
                                RegistryStat(value: detail.requiredDocs.count, label: "docs")
                                RegistryStat(value: detail.summary.requiredCount ?? detail.requiredDocs.count, label: "required")
                                RegistryStat(value: detail.gaps.count, label: "gaps")
                                RegistryStat(value: detail.summary.byDoctrineStatus?["canonical"] ?? 0, label: "canonical")
                            }

                            Text(detail.description)
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)

                            LazyVStack(spacing: Theme.xs) {
                                ForEach(detail.requiredDocs.prefix(8)) { item in
                                    RegistryDocRow(item: item)
                                }
                            }
                        }
                        .padding(.top, Theme.xs)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.doctrineBundleErrorMessage ?? "Doctrine bundles are unavailable from ORCA.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var reviewQueueSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Pod Review Queue", systemImage: "tray.full")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadReviewQueue()
                        await viewModel.loadRuntimeReviewQueue()
                        await viewModel.loadRuntimeSyncPreview()
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingReviewQueue || viewModel.isLoadingRuntimeReviewQueue || viewModel.isLoadingRuntimeSync ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingReviewQueue || viewModel.isLoadingRuntimeReviewQueue || viewModel.isLoadingRuntimeSync)
                .accessibilityLabel("Refresh Pod review queue")
            }

            if (viewModel.isLoadingReviewQueue || viewModel.isLoadingRuntimeReviewQueue) && viewModel.reviewQueueSummary == nil && viewModel.runtimeReviewSummary == nil {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading Pod review queue...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if viewModel.reviewQueueSummary != nil || viewModel.runtimeReviewSummary != nil {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        RegistryStat(value: viewModel.reviewQueueSummary?.total ?? 0, label: "docs")
                        RegistryStat(value: viewModel.runtimeReviewUnits.count, label: "runtime")
                        RegistryStat(value: viewModel.runtimeNeedsOwnerCount, label: "owner")
                        RegistryStat(value: viewModel.runtimeNeedsDocsCount, label: "docs gap")
                    }

                    if !viewModel.reviewQueueReviewers.isEmpty {
                        Text("Reviewers: \(viewModel.reviewQueueReviewers.joined(separator: ", "))")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    if let gate = viewModel.reviewQueueReleaseGate, !gate.isEmpty {
                        Text(gate)
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(3)
                    }

                    if let message = viewModel.reviewActionMessage {
                        Text(message)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.accentSuccess)
                            .lineLimit(2)
                    }

                    reviewSyncControls
                    runtimeSyncControls

                    if !viewModel.reviewQueueItems.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            Text("Docs needing doctrine review")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)

                            LazyVStack(spacing: Theme.xs) {
                                ForEach(viewModel.reviewQueueItems.prefix(6)) { item in
                                    RegistryDocRow(
                                        item: item,
                                        isReviewing: viewModel.reviewActionInFlightDocId == item.id,
                                        onReviewAction: { action in
                                            Task {
                                                await viewModel.applyReviewAction(action, to: item)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if !viewModel.runtimeReviewQueueItems.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            HStack(spacing: Theme.xs) {
                                Text("Runtime units needing review")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(AppColors.textSecondary)
                                Spacer()
                                if let generatedAt = viewModel.runtimeReviewGeneratedAt {
                                    Text(generatedAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }

                            LazyVStack(spacing: Theme.xs) {
                                ForEach(viewModel.runtimeReviewQueueItems.prefix(6)) { item in
                                    RuntimeReviewUnitRow(item: item)
                                }
                            }
                        }
                    } else if viewModel.runtimeReviewSummary != nil {
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "checkmark.seal")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.accentSuccess)
                            Text("No runtime registry review gaps detected.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(Theme.xs)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }

                    if let message = viewModel.runtimeReviewQueueErrorMessage {
                        Text("Runtime review unavailable: \(message)")
                            .font(.caption2)
                            .foregroundColor(AppColors.accentWarning)
                            .lineLimit(2)
                    }

                    if (viewModel.reviewQueueSummary?.total ?? 0) == 0 && viewModel.runtimeReviewUnits.isEmpty {
                        Text("Aloha and Coral have no docs or runtime units waiting in this queue.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.xs)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.reviewQueueErrorMessage ?? "Doctrine review queue is unavailable from ORCA.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var notesAndDecisionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Notes & Decisions", systemImage: "note.text")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task {
                        await viewModel.exportNoteGovernance(filter: noteFilter)
                    }
                } label: {
                    Image(systemName: viewModel.isExportingNoteGovernance ? "hourglass" : "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentAgent)
                }
                .disabled(viewModel.isExportingNoteGovernance)
                .accessibilityLabel("Export note governance review packet")

                Button {
                    Task {
                        await viewModel.loadNotes(filter: noteFilter)
                    }
                } label: {
                    Image(systemName: viewModel.isLoadingNotes ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingNotes)
                .accessibilityLabel("Refresh ORCA notes and decisions")
            }

            Picker("Note filter", selection: $noteFilter) {
                ForEach(OrcaNoteFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: noteFilter) { _, newValue in
                Task {
                    await viewModel.loadNotes(filter: newValue)
                }
            }

            if noteFilter == .finding {
                HStack(spacing: Theme.xs) {
                    Image(systemName: "checklist.checked")
                        .font(.caption)
                        .foregroundColor(AppColors.accentAgent)
                    Text("Findings are governed ORCA notes from /api/v1/notes/findings.")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                }
                .padding(Theme.sm)
                .background(AppColors.accentAgent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }

            if let audit = viewModel.noteGovernanceAudit {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(spacing: Theme.xs) {
                        RegistryStat(value: audit.total, label: "notes")
                        RegistryStat(value: audit.decisionNotesMissingGovernance, label: "decisions need review")
                        RegistryStat(value: audit.missingTraceId, label: "missing trace")
                    }

                    Text(audit.recommendedNextAction)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)

                    if let message = viewModel.noteGovernanceExportMessage {
                        Text(message)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.accentAgent)
                    }

                    if let path = viewModel.noteGovernanceExport?.markdownPath {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    if let error = viewModel.noteGovernanceErrorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(AppColors.accentDanger)
                            .lineLimit(2)
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }

            if let queue = viewModel.noteGovernanceQueue, queue.total > 0 {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "signature")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentWarning)
                        Text("Governance Queue")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text("\(queue.total)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(AppColors.accentWarning)
                    }

                    ForEach(queue.items.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.note.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                            Text("Missing \(item.missingFields.joined(separator: ", ")) · owner \(item.recommendedOwner ?? "review") · reviewer \(item.recommendedReviewer ?? "review")")
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }

                    Text(queue.recommendedNextAction)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: Theme.xs) {
                HStack(spacing: Theme.xs) {
                    TextField("System note title", text: $newSystemNoteTitle)
                        .font(.caption.weight(.semibold))
                        .textInputAutocapitalization(.sentences)

                    Picker("Type", selection: $newSystemNoteType) {
                        Text("Decision").tag("decision")
                        Text("System").tag("system")
                        Text("Handoff").tag("handoff")
                        Text("Finding").tag("finding")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)
                }

                TextField("Write a durable ORCA note", text: $newSystemNoteBody, axis: .vertical)
                    .font(.caption)
                    .lineLimit(2...6)

                Button {
                    Task { await createSystemNote() }
                } label: {
                    HStack(spacing: Theme.xs) {
                        if isSavingSystemNote {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.pencil")
                        }
                        Text(isSavingSystemNote ? "Saving" : "Save ORCA Note")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundColor(AppColors.accentElectric)
                }
                .buttonStyle(.plain)
                .disabled(!canSaveSystemNote || isSavingSystemNote)

                if let systemNoteStatus {
                    Text(systemNoteStatus)
                        .font(.caption2)
                        .foregroundColor(systemNoteStatus.localizedCaseInsensitiveContains("couldn't") ? AppColors.accentDanger : AppColors.textTertiary)
                }
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

            if viewModel.isLoadingNotes && viewModel.notes.isEmpty {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading ORCA notes...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if !viewModel.notes.isEmpty {
                LazyVStack(spacing: Theme.xs) {
                    ForEach(viewModel.notes.prefix(8)) { note in
                        OrcaNoteRow(note: note) {
                            selectedNote = note
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.notesErrorMessage ?? "No ORCA notes or decisions yet.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var skillLabSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Skill Lab", systemImage: "wand.and.stars")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task { await viewModel.loadSkillLab() }
                } label: {
                    Image(systemName: viewModel.isLoadingSkillLab ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingSkillLab)
                .accessibilityLabel("Refresh Skill Lab")
            }

            if viewModel.isLoadingSkillLab && viewModel.skillLabOverview == nil {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading Skill Lab...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if let overview = viewModel.skillLabOverview {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    HStack(spacing: Theme.sm) {
                        RegistryStat(value: overview.counts["skills"] ?? overview.skills.count, label: "skills")
                        RegistryStat(value: overview.counts["eval_cases"] ?? 0, label: "cases")
                        RegistryStat(value: overview.counts["pending_promotions"] ?? overview.pendingPromotions.count, label: "pending")
                        RegistryStat(value: overview.counts["recent_eval_runs"] ?? overview.recentEvalRuns.count, label: "evals")
                    }

                    Text(overview.policy)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !overview.skills.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            Text("Registered skills")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)

                            ForEach(overview.skills.prefix(6)) { skill in
                                Button {
                                    selectedSkillLabSkill = skill
                                    Task { await viewModel.openSkillLabDetail(skill) }
                                } label: {
                                    SkillLabSkillRow(skill: skill)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !overview.pendingPromotions.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            Text("Promotion candidates")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)

                            ForEach(overview.pendingPromotions.prefix(5)) { candidate in
                                SkillLabPromotionRow(candidate: candidate)
                            }
                        }
                    }

                    if !overview.recentEvalRuns.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            Text("Recent eval runs")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.textSecondary)

                            ForEach(overview.recentEvalRuns.prefix(5)) { run in
                                SkillLabEvalRunRow(run: run)
                            }
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                Text(viewModel.skillLabErrorMessage ?? "Skill Lab is unavailable from ORCA.")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private var canSaveSystemNote: Bool {
        !newSystemNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !newSystemNoteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func createSystemNote() async {
        guard canSaveSystemNote else { return }
        isSavingSystemNote = true
        systemNoteStatus = nil
        defer { isSavingSystemNote = false }

        let saved = await viewModel.createSystemNote(
            title: newSystemNoteTitle,
            body: newSystemNoteBody,
            noteType: newSystemNoteType
        )
        if saved {
            newSystemNoteTitle = ""
            newSystemNoteBody = ""
            newSystemNoteType = "decision"
            systemNoteStatus = "ORCA note saved."
        } else {
            systemNoteStatus = "Couldn't save ORCA note."
        }
    }

    private var reviewSyncControls: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                if let preview = viewModel.reviewSyncPreview {
                    RegistryStat(value: preview.total, label: "reviewed")
                    RegistryStat(value: preview.byStatus["canonical"] ?? 0, label: "approved")
                    RegistryStat(value: preview.byStatus["quarantine"] ?? 0, label: "held")
                } else {
                    Text(viewModel.isLoadingReviewSync ? "Checking sync overlay..." : "No sync preview loaded")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        await viewModel.exportReviewSync()
                    }
                } label: {
                    if viewModel.isExportingReviewSync {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentElectric)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExportingReviewSync)
                .accessibilityLabel("Export doctrine review sync")
            }

            if let message = viewModel.reviewSyncMessage {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.accentSuccess)
                    .lineLimit(2)
            }

            if !viewModel.reviewSyncExports.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.reviewSyncExports.prefix(3)) { artifact in
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppColors.accentElectric)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artifact.exportId)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(artifact.markdownPath)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.xs)
                            Text(artifact.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
                .padding(Theme.xs)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    private var runtimeSyncControls: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                if let preview = viewModel.runtimeSyncPreview {
                    RegistryStat(value: preview.total, label: "runtime")
                    RegistryStat(value: preview.byAction["keep"] ?? 0, label: "keep")
                    RegistryStat(value: preview.byAction["retire"] ?? 0, label: "retire")
                } else {
                    Text(viewModel.isLoadingRuntimeSync ? "Checking runtime handoff..." : "No runtime sync preview loaded")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await viewModel.loadRuntimeSyncPreview() }
                } label: {
                    Image(systemName: viewModel.isLoadingRuntimeSync ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingRuntimeSync)
                .accessibilityLabel("Preview runtime classification sync")

                Button {
                    Task { await viewModel.exportRuntimeSync() }
                } label: {
                    if viewModel.isExportingRuntimeSync {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentAgent)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExportingRuntimeSync || (viewModel.runtimeSyncPreview?.total ?? 0) == 0)
                .accessibilityLabel("Export runtime classification sync")

                Button {
                    Task { await viewModel.exportRuntimeBurnDown() }
                } label: {
                    if viewModel.isExportingRuntimeBurnDown {
                        ProgressView()
                            .scaleEffect(0.65)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentWarning)
                            .frame(width: 28, height: 28)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExportingRuntimeBurnDown)
                .accessibilityLabel("Export full runtime burn down")
            }

            if let preview = viewModel.runtimeSyncPreview, !preview.byAction.isEmpty {
                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(preview.byAction.sorted(by: { $0.key < $1.key }), id: \.key) { action, count in
                        Text("\(action.replacingOccurrences(of: "_", with: " ")) \(count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppColors.backgroundTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }
            }

            if let message = viewModel.runtimeSyncMessage {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.accentSuccess)
                    .lineLimit(2)
            }

            if let message = viewModel.runtimeBurnDownMessage {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(AppColors.accentWarning)
                    .lineLimit(2)
            }

            if !viewModel.runtimeSyncExports.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.runtimeSyncExports.prefix(3)) { artifact in
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppColors.accentAgent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artifact.exportId)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(artifact.markdownPath)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.xs)
                            Text(artifact.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
                .padding(Theme.xs)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            if !viewModel.runtimeBurnDownExports.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.runtimeBurnDownExports.prefix(2)) { artifact in
                        HStack(spacing: Theme.xs) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppColors.accentWarning)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artifact.exportId)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                Text(artifact.markdownPath)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.xs)
                            Text(artifact.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
                .padding(Theme.xs)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
        .padding(.top, Theme.xs)
    }

    private var memoryCandidatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Label("Memory Candidates", systemImage: "brain.head.profile")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Task { await viewModel.generateMemoryPromotionTicket() }
                } label: {
                    if viewModel.isGeneratingMemoryPromotionTicket {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGeneratingMemoryPromotionTicket)
                .accessibilityLabel("Create or update memory promotion review ticket")

                Button {
                    Task { await viewModel.generateStorageHygieneTicket() }
                } label: {
                    if viewModel.isGeneratingStorageHygieneTicket {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "text.badge.checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentAgent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGeneratingStorageHygieneTicket)
                .accessibilityLabel("Create or update storage hygiene ticket")

                Button {
                    Task { await viewModel.loadMemoryCandidates() }
                } label: {
                    Image(systemName: viewModel.isLoadingMemoryCandidates ? "hourglass" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accentElectric)
                }
                .disabled(viewModel.isLoadingMemoryCandidates)
                .accessibilityLabel("Refresh memory candidates")
            }

            if viewModel.isLoadingMemoryCandidates && viewModel.memoryCandidateQueue == nil {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Loading memory review queue...")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            } else if let queue = viewModel.memoryCandidateQueue {
                VStack(alignment: .leading, spacing: Theme.sm) {
                    if let message = viewModel.storageHygieneMessage {
                        Text(message)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(message.lowercased().contains("unavailable") ? AppColors.accentWarning : AppColors.accentSuccess)
                            .lineLimit(2)
                    }
                    if let message = viewModel.memoryPromotionMessage {
                        Text(message)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(message.lowercased().contains("unavailable") ? AppColors.accentWarning : AppColors.accentSuccess)
                            .lineLimit(2)
                    }
                    if let message = viewModel.memoryActionMessage {
                        Text(message)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(message.lowercased().contains("unavailable") ? AppColors.accentWarning : AppColors.accentSuccess)
                            .lineLimit(2)
                    }

                    HStack(spacing: Theme.sm) {
                        RegistryStat(value: queue.items.count, label: "candidates")
                        RegistryStat(value: viewModel.dailyLogExtraction?.records.count ?? 0, label: "logs")
                        RegistryStat(value: viewModel.dailyLogExtraction?.summary.presentAgents.count ?? 0, label: "agents")
                        RegistryStat(value: viewModel.durablePendingCount, label: "pending")
                        RegistryStat(value: viewModel.memoryLifecycleCounts["approved"] ?? 0, label: "approved")
                    }

                    if let ops = viewModel.memoryOps {
                        memoryOpsRow(ops)
                    }

                    if let extraction = viewModel.dailyLogExtraction {
                        dailyLogCoverageRow(extraction.summary)
                    }

                    memorySearchSurface

                    if let generatedAt = queue.generatedAt {
                        Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    LazyVStack(alignment: .leading, spacing: Theme.sm) {
                        ForEach(memoryCandidateGroups(for: queue.items)) { group in
                            VStack(alignment: .leading, spacing: Theme.xs) {
                                HStack(spacing: Theme.xs) {
                                    Text(group.title.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(AppColors.textTertiary)
                                    Text("\(group.items.count)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(group.color)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(group.color.opacity(0.12))
                                        .clipShape(Capsule())
                                    Spacer(minLength: 0)
                                }

                                ForEach(group.items) { item in
                                    MemoryCandidateRow(
                                        candidate: item,
                                        isBusy: viewModel.memoryActionCandidateIds.contains(item.id),
                                        approvalLockReason: approvalLockReason(for: item),
                                        onApproveChroma: {
                                            Task { await viewModel.approveMemoryCandidate(item, target: "chroma") }
                                        },
                                        onApproveAgentMemory: {
                                            Task { await viewModel.approveMemoryCandidate(item, target: "agent_memory_md") }
                                        },
                                        onReject: {
                                            Task { await viewModel.rejectMemoryCandidate(item) }
                                        },
                                        onDefer: {
                                            Task { await viewModel.deferMemoryCandidate(item) }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    if let message = viewModel.storageHygieneMessage {
                        Text(message)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(message.lowercased().contains("unavailable") ? AppColors.accentWarning : AppColors.accentSuccess)
                    }
                    Text(viewModel.memoryCandidatesErrorMessage ?? "Memory candidate queue is unavailable from ORCA.")
                        .font(.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sm)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
        }
    }

    private func dailyLogCoverageRow(_ summary: DailyLogExtractionSummary) -> some View {
        let coverage = summary.coverageStatus.replacingOccurrences(of: "_", with: " ").capitalized
        let missing = summary.missingAgents.joined(separator: ", ")
        let present = summary.presentAgents.joined(separator: ", ")
        let isComplete = summary.coverageStatus == "complete"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(isComplete ? AppColors.accentSuccess : AppColors.accentWarning)
                Text("Daily coverage: \(coverage)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
            }

            if !missing.isEmpty {
                Text("Missing: \(missing)")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .lineLimit(2)
            } else if !present.isEmpty {
                Text("Present: \(present)")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func memoryOpsRow(_ ops: MemoryOpsResponse) -> some View {
        let coverage = ops.coverageStatus.replacingOccurrences(of: "_", with: " ").capitalized
        let laneTitle = ops.laneMode.replacingOccurrences(of: "_", with: " ").capitalized
        let isComplete = ops.coverageStatus == "complete"
        let missing = ops.missingAgents.joined(separator: ", ")
        let present = ops.presentAgents.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentElectric)
                Text("Lane: \(laneTitle)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                Spacer(minLength: 0)
                Text("\(ops.durableTotal) durable")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.accentElectric)
            }

            HStack(spacing: Theme.sm) {
                Text("Pending \(ops.pendingReview)")
                Text("Sensitive \(ops.sensitiveWaiting)")
                Text("Extract \(ops.latestExtractCandidates)")
            }
            .font(.caption2)
            .foregroundColor(AppColors.textTertiary)

            HStack(spacing: Theme.xs) {
                Image(systemName: isComplete ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(isComplete ? AppColors.accentSuccess : AppColors.accentWarning)
                Text("Coverage: \(coverage)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
            }

            if !missing.isEmpty {
                Text("Missing: \(missing)")
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
                    .lineLimit(2)
            } else if !present.isEmpty {
                Text("Present: \(present)")
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var memorySearchSurface: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            HStack(spacing: Theme.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(AppColors.textTertiary)

                TextField("Search durable memory, fish research, Chief graph…", text: $viewModel.memoryQueryText)
                    .font(.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await viewModel.queryMemory() }
                    }

                if viewModel.isLoadingMemoryQuery {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await viewModel.queryMemory() }
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentElectric)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Run memory query")
                }
            }
            .padding(.horizontal, Theme.xs)
            .padding(.vertical, Theme.xs)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

            if let error = viewModel.memoryQueryErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(AppColors.accentWarning)
            } else if let response = viewModel.memoryQueryResponse {
                if response.items.isEmpty {
                    Text("No memory matches yet.")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        HStack(spacing: Theme.xs) {
                            Text("MEMORY SEARCH")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppColors.textTertiary)
                            Text("\(response.total)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(AppColors.accentElectric)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accentElectric.opacity(0.12))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        ForEach(response.items.prefix(4)) { item in
                            MemoryQueryResultRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private func memoryCandidateGroups(for items: [DailyLogExtractionCandidate]) -> [MemoryCandidateGroup] {
        let groups: [(MemoryCandidateGroup.Kind, [DailyLogExtractionCandidate])] = [
            (.sensitive, items.filter { memoryGroupKind(for: $0) == .sensitive }),
            (.safe, items.filter { memoryGroupKind(for: $0) == .safe }),
            (.deferred, items.filter { memoryGroupKind(for: $0) == .deferred }),
            (.committed, items.filter { memoryGroupKind(for: $0) == .committed }),
            (.rejected, items.filter { memoryGroupKind(for: $0) == .rejected }),
            (.other, items.filter { memoryGroupKind(for: $0) == .other }),
        ]
        return groups
            .filter { !$0.1.isEmpty }
            .map { MemoryCandidateGroup(kind: $0.0, items: $0.1) }
    }

    private func memoryGroupKind(for candidate: DailyLogExtractionCandidate) -> MemoryCandidateGroup.Kind {
        let lifecycle = candidate.effectiveLifecycle.lowercased()
        if lifecycle == "deferred" { return .deferred }
        if lifecycle == "approved" || lifecycle == "promoted" || lifecycle == "committed" { return .committed }
        if lifecycle == "rejected" { return .rejected }
        if candidate.isSensitive || !candidate.pendingApprovals.isEmpty { return .sensitive }
        if ["candidate", "pending", "review_required", "needs_review"].contains(lifecycle) { return .safe }
        return .other
    }

    private func approvalLockReason(for candidate: DailyLogExtractionCandidate) -> String? {
        let reviewer = viewModel.reviewerIdentity
        let waitingOn = candidate.pendingApprovals.isEmpty ? candidate.requiredReviewers : candidate.pendingApprovals
        guard candidate.isSensitive || !waitingOn.isEmpty else { return nil }
        guard !waitingOn.isEmpty else { return "Sensitive candidate needs explicit reviewer gate." }
        guard waitingOn.contains(where: { $0.caseInsensitiveCompare(reviewer) == .orderedSame }) else {
            return "Approval locked until \(waitingOn.joined(separator: ", ")) reviews."
        }
        return nil
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.sm),
                GridItem(.flexible(), spacing: Theme.sm),
            ],
            spacing: Theme.sm
        ) {
            ForEach(StandardCategory.allCases, id: \.self) { category in
                CategoryCard(
                    category: category,
                    count: viewModel.categoryCounts[category] ?? 0,
                    isSelected: viewModel.selectedCategory == category
                ) {
                    withAnimation(Animation.easeInOut) {
                        if viewModel.selectedCategory == category {
                            viewModel.selectedCategory = nil
                        } else {
                            viewModel.selectedCategory = category
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Recent")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(viewModel.recentStandards) { standard in
                        RecentStandardCard(standard: standard) {
                            selectedStandard = standard
                        }
                    }
                }
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.accentWarning)

                Text("Favorites")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.sm) {
                    ForEach(viewModel.favoriteStandards) { standard in
                        FavoriteStandardCard(standard: standard) {
                            selectedStandard = standard
                        }
                    }
                }
            }
        }
    }

    // MARK: - Standards List

    private var standardsList: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
                Text(viewModel.selectedCategory?.displayName ?? "All Standards")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text("\(viewModel.filteredStandards.count)")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textTertiary)
            }

            if viewModel.isLoading && viewModel.standards.isEmpty {
                loadingView
            } else if viewModel.filteredStandards.isEmpty {
                emptyView
            } else {
                LazyVStack(spacing: Theme.xs) {
                    ForEach(viewModel.filteredStandards) { standard in
                        StandardRowView(standard: standard) {
                            selectedStandard = standard
                        } onFavorite: {
                            Task {
                                await viewModel.toggleFavorite(id: standard.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showingEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(AppColors.accentElectric)
                .clipShape(Circle())
                .podShadow(Theme.ShadowConfig.medium)
        }
        .padding(.trailing, Theme.md)
        .padding(.bottom, Theme.md)
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(AppColors.accentElectric)
            Spacer()
        }
        .frame(height: 200)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)

            Text("No standards found")
                .font(.headline)
                .foregroundColor(AppColors.textSecondary)

            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.xxl)
    }
}

// MARK: - Skill Lab Rows

private struct SkillLabSkillRow: View {
    let skill: SkillLabSkill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Image(systemName: skill.protected ? "lock.shield" : "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(skill.protected ? AppColors.accentWarning : AppColors.accentElectric)
                Text(skill.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.xs)
                Text(skill.status.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            Text(skill.purpose)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(2)

            Text("owner \(skill.ownerAgent) · safety \(skill.safetyOwner) · standards \(skill.standardsOwner) · \(skill.domain)")
                .font(.caption2.monospaced())
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

private struct SkillLabPromotionRow: View {
    let candidate: SkillLabPromotionCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Image(systemName: candidate.protected ? "exclamationmark.shield" : "person.crop.circle.badge.questionmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(candidate.protected ? AppColors.accentWarning : AppColors.accentAgent)
                Text(candidate.summary ?? "Skill promotion candidate")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: Theme.xs)
                Text(candidate.riskLevel)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.accentWarning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.accentWarning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }

            Text(candidate.reviewState.replacingOccurrences(of: "_", with: " "))
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)

            let reviewers = candidate.requiredReviewers ?? []
            if !reviewers.isEmpty {
                Text("required: \(reviewers.joined(separator: ", "))")
                    .font(.caption2.monospaced())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

private struct SkillLabEvalRunRow: View {
    let run: SkillLabEvalRun

    var body: some View {
        HStack(spacing: Theme.xs) {
            Image(systemName: run.accepted ? "checkmark.seal" : "chart.xyaxis.line")
                .font(.caption.weight(.semibold))
                .foregroundColor(run.accepted ? AppColors.accentSuccess : AppColors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.benchmarkName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Text(evalDetail)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.xs)
            Text(run.status)
                .font(.caption2.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var evalDetail: String {
        var parts: [String] = []
        if let score = run.validationScore {
            parts.append("val \(score.formatted(.number.precision(.fractionLength(2))))")
        }
        if let route = run.targetRoute, !route.isEmpty {
            parts.append("route \(route)")
        }
        parts.append("\(run.regressionCount) regressions")
        return parts.joined(separator: " · ")
    }
}

private struct SkillLabDetailSheet: View {
    let skill: SkillLabSkill
    let detail: SkillLabDetail?
    let isLoading: Bool
    let errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text(skill.title)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)

                        Text(skill.purpose)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("owner \(skill.ownerAgent) · safety \(skill.safetyOwner) · standards \(skill.standardsOwner)")
                            .font(.caption.monospaced())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    if isLoading && detail == nil {
                        HStack(spacing: Theme.xs) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Loading Skill Lab review packet...")
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    } else if let detail {
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack(spacing: Theme.sm) {
                                RegistryStat(value: detail.counts["versions"] ?? detail.versions.count, label: "versions")
                                RegistryStat(value: detail.counts["eval_cases"] ?? detail.evalCases.count, label: "cases")
                                RegistryStat(value: detail.counts["eval_runs"] ?? detail.evalRuns.count, label: "evals")
                                RegistryStat(value: detail.counts["promotion_candidates"] ?? detail.promotionCandidates.count, label: "promos")
                            }

                            Text(detail.policy)
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !detail.evalCases.isEmpty {
                            SkillLabDetailGroup(title: "Eval corpus", icon: "checklist") {
                                ForEach(detail.evalCases.prefix(12)) { evalCase in
                                    SkillLabEvalCaseRow(evalCase: evalCase)
                                }
                            }
                        }

                        if !detail.promotionCandidates.isEmpty {
                            SkillLabDetailGroup(title: "Promotion review", icon: "person.crop.circle.badge.questionmark") {
                                ForEach(detail.promotionCandidates.prefix(6)) { candidate in
                                    SkillLabPromotionRow(candidate: candidate)
                                }
                            }
                        }

                        if !detail.versions.isEmpty {
                            SkillLabDetailGroup(title: "Versions", icon: "doc.on.doc") {
                                ForEach(detail.versions.prefix(6)) { version in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(version.version)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppColors.textPrimary)
                                        Text("\(version.status) · \(version.source)")
                                            .font(.caption2)
                                            .foregroundColor(AppColors.textTertiary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Theme.xs)
                                    .background(AppColors.backgroundTertiary)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                }
                            }
                        }
                    } else {
                        Text(errorMessage ?? "Skill Lab detail is unavailable from ORCA.")
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Skill Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SkillLabDetailGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.sm)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

private struct SkillLabEvalCaseRow: View {
    let evalCase: SkillLabEvalCase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Image(systemName: evalCase.protected ? "lock.shield" : "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(evalCase.protected ? AppColors.accentWarning : AppColors.accentElectric)
                Text(evalCase.caseId.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.xs)
                Text(evalCase.expectedRiskLevel ?? "risk ?")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(evalCase.protected ? AppColors.accentWarning : AppColors.textSecondary)
            }

            Text(evalCase.inputText)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(3)

            Text("expect \(evalCase.expectedOwnerAgent ?? "?") · \(evalCase.expectedDeliveryMode ?? "?") · \(evalCase.expectedNextAction ?? "?")")
                .font(.caption2.monospaced())
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - Memory Candidate Row

private struct MemoryCandidateRow: View {
    let candidate: DailyLogExtractionCandidate
    let isBusy: Bool
    let approvalLockReason: String?
    let onApproveChroma: () -> Void
    let onApproveAgentMemory: () -> Void
    let onReject: () -> Void
    let onDefer: () -> Void

    var body: some View {
        PodReviewCard(item: reviewItem, isBusy: isBusy) { action in
            switch action.id {
            case "approve-chroma":
                onApproveChroma()
            case "approve-agent-memory":
                onApproveAgentMemory()
            case "reject":
                onReject()
            case "defer":
                onDefer()
            default:
                break
            }
        }
    }

    private var statusColor: Color {
        switch candidate.effectiveLifecycle.lowercased() {
        case "candidate", "pending", "review_required", "needs_review":
            return AppColors.accentWarning
        case "approved", "promoted", "green":
            return AppColors.accentSuccess
        case "deferred":
            return AppColors.accentElectric
        case "rejected":
            return AppColors.accentWarning
        default:
            return AppColors.textTertiary
        }
    }

    private var canTakeAction: Bool {
        candidate.candidateId?.isEmpty == false
    }

    private var canApprove: Bool {
        canTakeAction && approvalLockReason == nil
    }

    private var reviewItem: PodReviewItem {
        var provenance = [
            candidate.agent.capitalized,
            candidate.date,
        ]
        if let ticketRef = candidate.ticketRef, !ticketRef.isEmpty {
            provenance.append(ticketRef)
        }
        if let target = candidate.promotionTarget ?? candidate.target, !target.isEmpty {
            provenance.append("target \(target)")
        }
        if let reviewState = candidate.reviewState, !reviewState.isEmpty {
            provenance.append("review \(reviewState)")
        }
        if let sourcePath = candidate.sourcePath, !sourcePath.isEmpty {
            provenance.append(sourcePath)
        }
        if !candidate.requiredReviewers.isEmpty {
            provenance.append("review \(candidate.requiredReviewers.joined(separator: ","))")
        }
        if candidate.isSensitive, let sensitivity = candidate.sensitivityClass, !sensitivity.isEmpty {
            provenance.append(sensitivity)
        }
        if !candidate.pendingApprovals.isEmpty {
            provenance.append("pending \(candidate.pendingApprovals.joined(separator: ","))")
        }
        if let confidence = candidate.confidence {
            provenance.append("\(Int(confidence * 100))% confidence")
        }
        provenance.append(contentsOf: candidate.tags.prefix(3).map { "#\($0)" })
        let detail = [candidate.reviewReason, approvalLockReason]
            .compactMap { value -> String? in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return PodReviewItem(
            id: candidate.id,
            eyebrow: "Memory candidate",
            title: candidate.text,
            detail: detail.isEmpty ? nil : detail,
            status: candidate.effectiveLifecycle.replacingOccurrences(of: "_", with: " "),
            statusColor: statusColor,
            provenance: provenance,
            traceId: candidate.decisionId,
            artifactHash: candidate.promotionArtifactPath,
            actions: [
                PodReviewAction(
                    id: "approve-chroma",
                    title: "Chroma",
                    systemImage: "externaldrive.badge.checkmark",
                    style: .success,
                    isDisabled: !canApprove || candidate.effectiveLifecycle == "approved"
                ),
                PodReviewAction(
                    id: "approve-agent-memory",
                    title: "Memory.md",
                    systemImage: "book.closed",
                    style: .primary,
                    isDisabled: !canApprove || candidate.effectiveLifecycle == "approved"
                ),
                PodReviewAction(
                    id: "defer",
                    title: "Defer",
                    systemImage: "clock.badge",
                    style: .neutral,
                    isDisabled: !canTakeAction
                ),
                PodReviewAction(
                    id: "reject",
                    title: "Reject",
                    systemImage: "xmark",
                    style: .destructive,
                    isDisabled: !canTakeAction || candidate.effectiveLifecycle == "rejected"
                ),
            ]
        )
    }
}

private struct MemoryQueryResultRow: View {
    let item: MemoryQueryResult

    private var sourceColor: Color {
        switch item.scope {
        case "chief_graph":
            return AppColors.accentWarning
        case "durable":
            return AppColors.accentSuccess
        default:
            return AppColors.accentElectric
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.xs) {
                Text(item.sourceLabel.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundColor(sourceColor)
                if item.protected {
                    Text("PROTECTED")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(AppColors.accentWarning)
                }
                Spacer()
                Text(String(format: "%.1f", item.score))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)

            Text(item.snippet)
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(3)

            if let path = item.path, !path.isEmpty {
                Text(path)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

private struct MemoryCandidateGroup: Identifiable {
    enum Kind: String {
        case sensitive
        case safe
        case deferred
        case committed
        case rejected
        case other
    }

    let kind: Kind
    let items: [DailyLogExtractionCandidate]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .sensitive: return "Sensitive / gated"
        case .safe: return "Safe review"
        case .deferred: return "Deferred"
        case .committed: return "Committed"
        case .rejected: return "Rejected"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch kind {
        case .sensitive: return AppColors.accentWarning
        case .safe: return AppColors.accentElectric
        case .deferred: return AppColors.textSecondary
        case .committed: return AppColors.accentSuccess
        case .rejected: return AppColors.accentDanger
        case .other: return AppColors.textTertiary
        }
    }
}

private struct CandidateChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - ORCA Notes

private struct OrcaNoteRow: View {
    let note: OrcaNote
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Theme.xs) {
                Image(systemName: iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Theme.xs) {
                        Text(note.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: Theme.xs)

                        Text(note.typeLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(iconColor)
                            .lineLimit(1)
                    }

                    Text(note.body)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.xs) {
                        CandidateChip(text: note.scopeLabel, icon: "scope")

                        if let source = note.source, !source.isEmpty {
                            CandidateChip(text: source, icon: "tray")
                        }

                        if let signState = note.signState, !signState.isEmpty {
                            CandidateChip(text: signState.replacingOccurrences(of: "_", with: " "), icon: "signature")
                        }

                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                    }

                    if let tags = note.tags, !tags.isEmpty {
                        HStack(spacing: Theme.xs) {
                            ForEach(tags.prefix(4), id: \.self) { tag in
                                CandidateChip(text: tag, icon: "tag")
                            }
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(.vertical, Theme.xs)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch note.noteType {
        case "decision", "decision_note":
            return "checkmark.seal"
        case "system":
            return "server.rack"
        default:
            return "note.text"
        }
    }

    private var iconColor: Color {
        switch note.noteType {
        case "decision", "decision_note":
            return AppColors.accentSuccess
        case "system":
            return AppColors.accentAgent
        default:
            return AppColors.accentElectric
        }
    }
}

private struct OrcaNoteDetailSheet: View {
    let note: OrcaNote

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text(note.typeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentElectric)

                        Text(note.title)
                            .font(.title3.weight(.bold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Theme.sm) {
                        noteFact("Scope", value: note.scopeLabel)
                        noteFact("Source", value: note.source)
                        noteFact("Author", value: note.createdBy)
                        noteFact("Owner", value: note.owner)
                        noteFact("Reviewer", value: note.reviewer)
                        noteFact("Sign state", value: note.signState?.replacingOccurrences(of: "_", with: " "))
                        noteFact("Trace", value: note.traceId)
                        noteFact("Updated", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding(Theme.sm)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))

                    Text(note.body)
                        .font(.body)
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let tags = note.tags, !tags.isEmpty {
                        FlowLayout(horizontalSpacing: Theme.xs, verticalSpacing: Theme.xs) {
                            ForEach(tags, id: \.self) { tag in
                                CandidateChip(text: tag, icon: "tag")
                            }
                        }
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("ORCA Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func noteFact(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: 72, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Wiki Mirror

private struct WikiMirrorRow: View {
    let document: WikiDocument
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Theme.xs) {
                Image(systemName: "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(document.path)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: Theme.xs) {
                        Text(document.section)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.accentAgent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())

                        Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.textMuted)
            }
            .padding(Theme.xs)
            .background(AppColors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}

private struct WikiDocumentMirrorSheet: View {
    let document: WikiDocument
    let isLoading: Bool
    let errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Text(document.title)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(document.path)
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)

                        HStack(spacing: Theme.xs) {
                            Text(document.section)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(AppColors.accentAgent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppColors.accentAgent.opacity(0.12))
                                .clipShape(Capsule())

                            Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    if isLoading && document.content == nil {
                        HStack(spacing: Theme.xs) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Loading mirrored document...")
                                .font(.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.sm)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(AppColors.accentDanger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.sm)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    } else {
                        Text(document.content ?? "")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.sm)
                            .background(AppColors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Wiki Mirror")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppColors.accentElectric)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Doctrine Bundle Row

private struct DoctrineBundleRow: View {
    let bundle: DoctrineBundleSummary
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.xs) {
            Image(systemName: isSelected ? "checkmark.seal.fill" : "square.stack.3d.up")
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? AppColors.accentSuccess : AppColors.accentElectric)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.xs) {
                    Text(bundle.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.xs)

                    Text("\(bundle.presentCount)/\(bundle.requiredCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(bundle.gapCount == 0 ? AppColors.accentSuccess : AppColors.accentWarning)
                        .lineLimit(1)
                }

                Text(bundle.purpose)
                    .font(.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.xs) {
                    Text(bundle.owner)
                    Text(bundle.requiredForAgents.joined(separator: ", "))
                    if bundle.gapCount > 0 {
                        Text("\(bundle.gapCount) gaps")
                            .foregroundColor(AppColors.accentWarning)
                    }
                }
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.xs)
    }
}

// MARK: - Registry Stat

private struct RegistryStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.caption2)
                .foregroundColor(AppColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.xs)
        .padding(.horizontal, Theme.xs)
        .background(AppColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}

// MARK: - Registry Doc Row

private struct RegistryDocRow: View {
    let item: DocRegistryItem
    var isReviewing: Bool = false
    var onReviewAction: ((DoctrineReviewAction) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.xs) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.accentElectric)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.xs) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.xs)

                    Text(item.kind.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Text(item.path)
                    .font(.caption2)
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)

                HStack(spacing: Theme.xs) {
                    Text(item.source.replacingOccurrences(of: "_", with: " "))
                    if let owner = item.owner {
                        Text(owner)
                    }
                    Text(item.doctrineStatus ?? "unknown")
                    Text("Chroma \(item.chromaStatus)")
                }
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)

                if let required = item.requiredForAgents, !required.isEmpty {
                    HStack(spacing: Theme.xs) {
                        Image(systemName: "checkmark.seal")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.accentSuccess)
                        Text("Required for \(required.joined(separator: ", "))")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                if let petal = item.enforcedByPetal, !petal.isEmpty {
                    Text("Enforced by \(petal)")
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                if let note = item.doctrineNote, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(AppColors.accentWarning)
                        .lineLimit(2)
                }

                if let onReviewAction {
                    reviewActions(onReviewAction)
                }
            }
        }
        .padding(.vertical, Theme.xs)
    }

    private func reviewActions(_ onReviewAction: @escaping (DoctrineReviewAction) -> Void) -> some View {
        HStack(spacing: Theme.xs) {
            if isReviewing {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 24, height: 24)
            } else {
                ForEach([
                    DoctrineReviewAction.promoteToCanonical,
                    DoctrineReviewAction.markDraft,
                    DoctrineReviewAction.markSuperseded,
                    DoctrineReviewAction.markArchived,
                ], id: \.self) { action in
                    Button {
                        onReviewAction(action)
                    } label: {
                        Text(action.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, Theme.xs)
                            .padding(.vertical, 5)
                            .background(actionBackground(action))
                            .foregroundColor(actionForeground(action))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                    .buttonStyle(.plain)
                    .disabled(isReviewing)
                }
            }
        }
        .padding(.top, 2)
    }

    private func actionBackground(_ action: DoctrineReviewAction) -> Color {
        switch action {
        case .promoteToCanonical:
            return AppColors.accentSuccess.opacity(0.14)
        case .markDraft:
            return AppColors.accentElectric.opacity(0.12)
        case .markSuperseded:
            return AppColors.accentWarning.opacity(0.14)
        case .markArchived:
            return AppColors.backgroundTertiary
        case .keepQuarantined:
            return AppColors.backgroundTertiary
        }
    }

    private func actionForeground(_ action: DoctrineReviewAction) -> Color {
        switch action {
        case .promoteToCanonical:
            return AppColors.accentSuccess
        case .markDraft:
            return AppColors.accentElectric
        case .markSuperseded:
            return AppColors.accentWarning
        case .markArchived:
            return AppColors.textSecondary
        case .keepQuarantined:
            return AppColors.textSecondary
        }
    }

    private var iconName: String {
        switch item.kind {
        case "dds": return "doc.badge.gearshape"
        case "charter": return "scroll"
        case "sop": return "checklist"
        case "tool": return "wrench.and.screwdriver"
        case "memory", "daily": return "brain.head.profile"
        case "chronogram": return "clock.badge.checkmark"
        default: return "doc.text"
        }
    }
}

// MARK: - Runtime Review Unit Row

private struct RuntimeReviewUnitRow: View {
    let item: PodRuntimeReviewQueueItem

    private var unit: PodRuntimeReviewUnit { item.unit }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.xs) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: Theme.xs) {
                    Text(unit.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: Theme.xs)

                    Text(unit.kind.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                HStack(spacing: Theme.xs) {
                    Text(unit.status)
                    if let owner = unit.owner, !owner.isEmpty {
                        Text(owner)
                    }
                    if let cadence = unit.cadence, !cadence.isEmpty {
                        Text(cadence)
                    }
                    if let pid = unit.pid {
                        Text("pid \(pid)")
                    }
                }
                .font(.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.suggestedAction.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(AppColors.accentAgent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColors.accentAgent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))

                    ForEach(item.followupReasons.prefix(3), id: \.self) { reason in
                        Text(reason.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(reasonColor(reason))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(reasonColor(reason).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }

                if let scriptPath = unit.scriptPath, !scriptPath.isEmpty {
                    Text(scriptPath)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                if let note = unit.classificationNote, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Theme.xs)
    }

    private var iconName: String {
        switch unit.kind {
        case "petal": return "leaf.fill"
        case "watchdog": return "shield.lefthalf.filled"
        case "bridge": return "point.3.connected.trianglepath.dotted"
        case "worker": return "hammer.fill"
        default: return "gearshape.fill"
        }
    }

    private var statusColor: Color {
        switch unit.status {
        case "running": return AppColors.accentSuccess
        case "loaded", "script_only": return AppColors.accentElectric
        case "disabled": return AppColors.textTertiary
        default: return AppColors.accentWarning
        }
    }

    private func reasonColor(_ reason: String) -> Color {
        if reason == "unclassified" {
            return AppColors.accentElectric
        }
        if reason.contains("exit") {
            return AppColors.accentDanger
        }
        return AppColors.accentWarning
    }
}

// MARK: - Category Card

private struct CategoryCard: View {
    let category: StandardCategory
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xs) {
                HStack {
                    Image(systemName: category.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hexString: category.color) : AppColors.textSecondary)

                    Spacer()

                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? Color(hexString: category.color) : AppColors.textTertiary)
                }

                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            }
            .padding(Theme.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(isSelected ? Color(hexString: category.color).opacity(0.15) : AppColors.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(isSelected ? Color(hexString: category.color) : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Standard Card

private struct RecentStandardCard: View {
    let standard: Standard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xxs) {
                HStack(spacing: Theme.xxs) {
                    Image(systemName: standard.category.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hexString: standard.category.color))

                    Text(standard.category.displayName)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)
                }

                Text(standard.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Theme.sm)
            .frame(width: 140, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Favorite Standard Card

private struct FavoriteStandardCard: View {
    let standard: Standard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Theme.xxs) {
                HStack(spacing: Theme.xxs) {
                    Image(systemName: standard.category.icon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hexString: standard.category.color))

                    Text(standard.category.displayName)
                        .font(.caption2)
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(AppColors.accentWarning)
                }

                Text(standard.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Theme.sm)
            .frame(width: 140, alignment: .leading)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standard Row View

struct StandardRowView: View {
    let standard: Standard
    let onTap: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.sm) {
                // Category indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hexString: standard.category.color))
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(standard.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: Theme.xs) {
                        CategoryBadge(category: standard.category)

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.caption2)

                        Text(standard.authorName)
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)

                        Text("•")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.caption2)

                        Text(standard.updatedAt.shortDateString)
                            .font(.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    if !standard.tags.isEmpty {
                        HStack(spacing: Theme.xxs) {
                            ForEach(standard.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColors.backgroundTertiary)
                                    .clipShape(Capsule())
                            }
                            if standard.tags.count > 3 {
                                Text("+\(standard.tags.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                }

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: standard.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(standard.isFavorite ? AppColors.accentWarning : AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Knowledge Packet Search

private struct KnowledgePacketResultRow: View {
    let packet: KnowledgePacketSearchResult
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: packet.sourceIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accentElectric)
                    .frame(width: 24, height: 24)
                    .background(AppColors.accentElectric.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(packet.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2)

                        Spacer(minLength: 6)

                        Text(packet.displayLane)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AppColors.accentAgent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !packet.body.isEmpty {
                        Text(packet.body)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 6) {
                        Text(packet.sourceType.replacingOccurrences(of: "_", with: " "))
                        if let evidenceRef = packet.evidenceRef, !evidenceRef.isEmpty {
                            Text(String(evidenceRef.prefix(36)))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct KnowledgePacketDetailSheet: View {
    let packet: KnowledgePacketSearchResult
    @Environment(\.dismiss) private var dismiss
    @State private var copiedEvidence = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    HStack(spacing: 8) {
                        Label(packet.sourceType.replacingOccurrences(of: "_", with: " "), systemImage: packet.sourceIcon)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accentElectric)

                        Text(packet.displayLane)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(AppColors.accentAgent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accentAgent.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(packet.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(packet.body.isEmpty ? "No packet body returned." : packet.body)
                        .font(.body)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let evidenceRef = packet.evidenceRef, !evidenceRef.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EVIDENCE REF")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.textTertiary)

                            HStack(alignment: .top, spacing: 8) {
                                Text(evidenceRef)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(AppColors.textSecondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Button {
                                    UIPasteboard.general.string = evidenceRef
                                    copiedEvidence = true
                                } label: {
                                    Image(systemName: copiedEvidence ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(copiedEvidence ? AppColors.accentSuccess : AppColors.accentElectric)
                                        .frame(width: 30, height: 30)
                                        .background(AppColors.backgroundTertiary)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy evidence reference")
                            }
                        }
                        .padding(Theme.sm)
                        .background(AppColors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    }
                }
                .padding(Theme.md)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Packet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: StandardCategory

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: category.icon)
                .font(.system(size: 8, weight: .semibold))

            Text(category.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(Color(hexString: category.color))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(hexString: category.color).opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Date Extensions

extension Date {
    var shortDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var versionDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - Preview

#Preview {
    KnowledgeView()
        .preferredColorScheme(.dark)
}
