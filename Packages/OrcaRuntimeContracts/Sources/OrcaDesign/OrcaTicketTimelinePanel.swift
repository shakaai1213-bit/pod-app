import SwiftUI
import OrcaDomain

/// Pod and Console use the same rows, ownership state, and server permissions.
public struct OrcaTicketTimelinePanel: View {
    let ticketID: String
    let recipients: [OrcaTicketRecipient]
    let load: @MainActor (OrcaTicketTimelineCursor?) async throws -> OrcaTicketTimelinePage
    let write: @MainActor (OrcaTicketEntryInput) async throws -> Void
    @State private var page: OrcaTicketTimelinePage?
    @State private var entries: [OrcaTicketEntry] = []
    @State private var pendingInput: OrcaTicketEntryInput?
    @State private var notice: String?
    @State private var busy = false
    @State private var draft = Draft()
    @State private var retryKey = UUID()

    public init(ticketID: String, recipients: [OrcaTicketRecipient],
        initialPage: OrcaTicketTimelinePage? = nil,
        load: @escaping @MainActor (OrcaTicketTimelineCursor?) async throws -> OrcaTicketTimelinePage,
        write: @escaping @MainActor (OrcaTicketEntryInput) async throws -> Void) {
        self.ticketID = ticketID; self.recipients = recipients; self.load = load; self.write = write
        _page = State(initialValue: initialPage); _entries = State(initialValue: initialPage?.entries ?? [])
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Ticket history", systemImage: "clock.arrow.circlepath"); Spacer()
                Button("Refresh") { Task { await refresh() } }.disabled(busy) }
            if let page {
                ownershipRow(page.ownership)
                if entries.isEmpty { Text("No entries yet.").foregroundStyle(.secondary) }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top) {
                            Text(entry.authorLabel).font(.subheadline.bold())
                            Spacer(); Text(entry.kindLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(entry.modelLabel) · \(entry.createdAt)").font(.caption).foregroundStyle(.secondary)
                        if let request = entry.details.onBehalfOf { Text("On behalf of: \(request) (declared context)").font(.caption) }
                        Text(entry.message).textSelection(.enabled)
                        if let from = entry.details.completed { Text("Done: \(from)").font(.caption) }
                        if let remaining = entry.details.remaining { Text("Remaining: \(remaining)").font(.caption) }
                        if let done = entry.details.definitionOfDone { Text("Complete when: \(done)").font(.caption) }
                        if let verdict = entry.details.verdict { Text("Review: \(verdict.replacingOccurrences(of: "_", with: " "))").font(.caption) }
                        if let tests = entry.details.testsSummary { Text("Tests: \(tests)").font(.caption) }
                        if let mutations = entry.details.mutationSummary { Text("Mutation checks: \(mutations)").font(.caption) }
                        if let pr = entry.details.prRef { Text("PR: \(pr)").font(.caption).textSelection(.enabled) }
                        if let original = entry.correctsEventID { Text("Corrects entry \(original)").font(.caption2.monospaced()).textSelection(.enabled) }
                        if let request = entry.requestEntryID { Text("Responds to \(request)").font(.caption2.monospaced()).textSelection(.enabled) }
                        if let head = entry.details.headSHA { Text(head).font(.caption.monospaced()).textSelection(.enabled) }
                        if let links = entry.details.evidence { ForEach(links, id: \.self) { Text($0).font(.caption).textSelection(.enabled) } }
                        Text("Entry \(entry.id)").font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        if page.permissions.canComment, UUID(uuidString: entry.id) != nil {
                            Button("Add correction") { draft = Draft(kind: "correction", correctsID: entry.id) }.font(.caption)
                        }
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(page.approvalRecords) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approval record · \(record.status)").font(.subheadline.bold())
                        Text(record.actionType).font(.caption)
                        Text("Signed record: \(record.signedRecordState) · Model unverified").font(.caption).foregroundStyle(.secondary)
                        if let name = record.declaredDecider { Text("Declared decider: \(name)").font(.caption) }
                        Text("This record has no verified approval authority.").font(.caption)
                        Text(record.pointer).font(.caption2.monospaced()).textSelection(.enabled)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                if page.nextBeforeGeneration != nil || page.nextLegacyBeforeID != nil {
                    Button("Load older entries") { Task { await loadOlder(page) } }.disabled(busy)
                }
                if page.permissions.canComment { composer(page) }
            } else if busy { ProgressView() }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: ticketID) { page = nil; draft = Draft(); await refresh() }
        .onChange(of: draft) { _, _ in retryKey = UUID(); pendingInput = nil }
    }
    private func ownershipRow(_ value: OrcaTicketOwnership) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let owner = value.ownerAgentID, let recipient = recipients.first(where: { $0.id.uuidString.lowercased() == owner.lowercased() }) {
                Text("Owner: \(recipient.name)").font(.subheadline)
            } else if value.ownerUserID != nil { Text("Owner: assigned user").font(.subheadline) }
            else if value.ownerAgentID != nil { Text("Owner: assigned agent").font(.subheadline) }
            else { Text("Owner: unassigned").font(.subheadline) }
            if value.awaitingAcknowledgement {
                if let due = value.dueAt { Text("Acknowledge by: \(due)").font(.caption) }
                Label(value.overdue ? "Acknowledgement overdue" : "Waiting for acknowledgement", systemImage: "person.badge.clock")
                if let id = value.handoffEntryID { Text("Handoff \(id)").font(.caption2.monospaced()).textSelection(.enabled) }
            } else if value.acknowledgedAt != nil { Label("Handoff acknowledged", systemImage: "checkmark.circle") }
        }
    }
    private func composer(_ page: OrcaTicketTimelinePage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Entry", selection: $draft.kind) {
                Text("Progress").tag("progress"); Text("Comment").tag("comment")
                if page.permissions.canClaim { Text("Claim").tag("claim") }
                if draft.kind == "correction" { Text("Correction").tag("correction") }
                if page.permissions.canReview { Text("Review").tag("review") }
                if page.permissions.canHandoff { Text("Handoff").tag("handoff") }
                if page.permissions.canAcknowledge { Text("Acknowledge").tag("acknowledge"); Text("Push back").tag("push_back") }
                if page.permissions.canChangeStatus { Text("Status").tag("status"); Text("Done").tag("done") }
            }
            TextField("On whose request? (optional)", text: $draft.onBehalfOf)
            TextField(draft.kind == "handoff" || draft.kind == "push_back" ? "Reason" : "What changed?", text: $draft.message, axis: .vertical)
            if ["handoff", "push_back"].contains(draft.kind) {
                Picker("Next owner", selection: $draft.recipientID) {
                    Text("Choose an agent").tag("")
                    ForEach(recipients) { Text($0.name).tag($0.id.uuidString) }
                }
            }
            if draft.kind == "handoff" {
                TextField("What is done", text: $draft.completed, axis: .vertical)
                TextField("What is left", text: $draft.remaining, axis: .vertical)
                TextField("Definition of done", text: $draft.definitionOfDone, axis: .vertical)
            }
            if draft.kind == "review" {
                Picker("Verdict", selection: $draft.verdict) { Text("Approve source").tag("approve"); Text("Hold").tag("hold"); Text("Request changes").tag("request_changes") }
                TextField("PR reference", text: $draft.prRef); TextField("Exact commit", text: $draft.headSHA)
                TextField("Test results", text: $draft.tests, axis: .vertical)
                TextField("Mutation checks", text: $draft.mutations, axis: .vertical)
                Text("A review entry does not replace a signed approval.").font(.caption).foregroundStyle(.secondary)
            }
            if draft.kind == "status" {
                Picker("Status", selection: $draft.targetStatus) {
                    Text("In progress").tag("in_progress"); Text("Blocked").tag("blocked"); Text("Open").tag("open"); Text("Cancelled").tag("cancelled")
                }
            }
            if draft.kind == "done" { TextField("Evidence links, one per line", text: $draft.evidence, axis: .vertical) }
            Button(busy ? "Saving…" : "Add entry") { Task { await submit(page) } }.disabled(busy || !draft.isValid)
        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    @MainActor private func refresh() async {
        busy = true; defer { busy = false }
        do { let result = try await load(nil); page = result; entries = result.entries; notice = nil }
        catch OrcaTicketTimelineError.accessDenied { page = nil; entries = []; notice = "This account does not have access to this ticket history." }
        catch OrcaTicketTimelineError.notActivated { notice = "Ticket history upgrade is awaiting activation." }
        catch { notice = "Ticket history could not be loaded. Refresh to retry." }
    }
    @MainActor private func loadOlder(_ page: OrcaTicketTimelinePage) async {
        busy = true; defer { busy = false }
        do {
            let older = try await load(OrcaTicketTimelineCursor(page: page))
            var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            for row in older.entries { byID[row.id] = row }
            entries = byID.values.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
            self.page = older; notice = nil
        } catch { notice = "Older history could not be loaded. Retry to continue." }
    }
    @MainActor private func submit(_ page: OrcaTicketTimelinePage) async {
        busy = true; defer { busy = false }
        do {
            var input = OrcaTicketEntryInput(kind: draft.kind, message: draft.message, idempotencyKey: retryKey, expectedGeneration: page.ownership.generation)
            input.onBehalfOf = draft.onBehalfOf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.onBehalfOf
            input.correctsEventID = draft.kind == "correction" ? UUID(uuidString: draft.correctsID) : nil
            if ["handoff", "push_back"].contains(draft.kind) { input.recipientAgentID = UUID(uuidString: draft.recipientID) }
            if ["acknowledge", "push_back"].contains(draft.kind) { input.handoffEntryID = page.ownership.handoffEntryID.flatMap(UUID.init(uuidString:)) }
            if draft.kind == "handoff" { input.completed = draft.completed; input.remaining = draft.remaining; input.definitionOfDone = draft.definitionOfDone }
            if draft.kind == "review" { input.verdict = draft.verdict; input.prRef = draft.prRef; input.headSHA = draft.headSHA; input.testsSummary = draft.tests; input.mutationSummary = draft.mutations }
            if draft.kind == "status" { input.targetStatus = draft.targetStatus }
            if draft.kind == "done" { input.evidence = draft.evidence.split(separator: "\n").map(String.init) }
            let request = pendingInput ?? input
            pendingInput = request
            try await write(request)
            pendingInput = nil; draft = Draft(); notice = "Entry saved."
            do { let updated = try await load(nil); self.page = updated; entries = updated.entries }
            catch { notice = "Entry saved. Refresh to update the history." }
        } catch OrcaTicketTimelineError.conflict {
            pendingInput = nil; retryKey = UUID()
            do { let updated = try await load(nil); self.page = updated; entries = updated.entries } catch {}
            notice = "The ticket changed. Review the latest history, then submit your draft again."
        } catch OrcaTicketTimelineError.accessDenied {
            pendingInput = nil; notice = "This account cannot add this entry."
        } catch OrcaTicketTimelineError.notActivated {
            notice = "Ticket writes are unavailable. Retry the same draft when service returns."
        } catch { notice = "Save could not be confirmed. Retry this draft, or refresh if ownership changed." }
    }
    private struct Draft: Equatable {
        var kind = "progress"; var onBehalfOf = ""; var correctsID = ""; var message = ""; var recipientID = ""
        var completed = ""; var remaining = ""; var definitionOfDone = ""; var verdict = "hold"
        var prRef = ""; var headSHA = ""; var tests = ""; var mutations = ""; var evidence = ""; var targetStatus = "in_progress"
        var isValid: Bool {
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            if kind == "correction" { return UUID(uuidString: correctsID) != nil }
            if ["handoff", "push_back"].contains(kind), UUID(uuidString: recipientID) == nil { return false }
            if kind == "handoff" { return !completed.isEmpty && !remaining.isEmpty && !definitionOfDone.isEmpty }
            if kind == "review" { return !prRef.isEmpty && headSHA.count == 40 && headSHA.allSatisfy { "0123456789abcdef".contains($0) } && !tests.isEmpty && !mutations.isEmpty }
            if kind == "done" { return !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
    }
}
