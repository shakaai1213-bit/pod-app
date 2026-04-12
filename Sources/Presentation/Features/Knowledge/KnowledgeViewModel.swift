import Foundation
import os.log

// MARK: - Knowledge ViewModel

@Observable
final class KnowledgeViewModel {

    // MARK: - Published State

    var standards: [Standard] = []
    var categories: [StandardCategory] = StandardCategory.allCases
    var selectedCategory: StandardCategory?
    var searchText: String = ""
    var recentStandards: [Standard] = []
    var favoriteStandards: [Standard] = []
    var isLoading: Bool = false
    var errorMessage: String?

    // MARK: - Computed

    var filteredStandards: [Standard] {
        var result = standards

        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { s in
                s.title.lowercased().contains(query) ||
                s.tags.contains { $0.lowercased().contains(query) } ||
                s.authorName.lowercased().contains(query)
            }
        }

        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    var categoryCounts: [StandardCategory: Int] {
        Dictionary(grouping: standards, by: \.category).mapValues(\.count)
    }

    // MARK: - Private

    private let recentStorageKey = "pod.recentStandards"
    private let favoritesStorageKey = "pod.favoriteStandards"

    // MARK: - Init

    init() {
        loadLocalFavorites()
        loadRecentStandards()
    }

    // MARK: - Load

    func loadStandards() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: PaginatedResponse<Standard> = try await APIClient.shared.get(path: "/api/v1/standards")
            await MainActor.run {
                self.standards = response.items
                self.recomputeDerived()
                self.isLoading = false
            }
        } catch {
            // API unavailable — fall back to mock data
            await MainActor.run {
                self.standards = Self.safeMockStandards()
                self.isLoading = false
            }
        }
    }

    func loadStandard(id: UUID) async -> Standard? {
        do {
            let standard: Standard = try await APIClient.shared.get(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == id }) {
                    standards[idx] = standard
                } else {
                    standards.append(standard)
                }
                addToRecent(standard)
            }
            return standard
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    // MARK: - Create

    func createStandard(_ standard: Standard) async -> Bool {
        do {
            let created: Standard = try await APIClient.shared.post(
                path: "/api/v1/standards",
                body: standard
            )
            await MainActor.run {
                standards.append(created)
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Update

    func updateStandard(_ standard: Standard) async -> Bool {
        do {
            let updated: Standard = try await APIClient.shared.put(
                path: "/api/v1/standards/\(standard.id.uuidString)",
                body: standard
            )
            await MainActor.run {
                if let idx = standards.firstIndex(where: { $0.id == standard.id }) {
                    standards[idx] = updated
                }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Delete

    func deleteStandard(id: UUID) async -> Bool {
        do {
            try await APIClient.shared.delete(path: "/api/v1/standards/\(id.uuidString)")
            await MainActor.run {
                standards.removeAll { $0.id == id }
                self.recomputeDerived()
            }
            return true
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    // MARK: - Favorite

    func toggleFavorite(id: UUID) async {
        if let idx = standards.firstIndex(where: { $0.id == id }) {
            standards[idx].isFavorite.toggle()
            await MainActor.run {
                recomputeDerived()
                persistFavorites()
            }
        }
    }

    // MARK: - Search

    func searchStandards(_ query: String) async -> [Standard] {
        guard !query.isEmpty else { return [] }

        do {
            let results: [Standard] = try await APIClient.shared.get(
                path: "/api/v1/standards/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
            )
            return results
        } catch {
            return []
        }
    }

    // MARK: - Recent

    private func addToRecent(_ standard: Standard) {
        recentStandards.removeAll { $0.id == standard.id }
        recentStandards.insert(standard, at: 0)
        if recentStandards.count > 20 {
            recentStandards = Array(recentStandards.prefix(20))
        }
        persistRecent()
    }

    private func loadRecentStandards() {
        if let data = UserDefaults.standard.data(forKey: recentStorageKey),
           let decoded = try? JSONDecoder().decode([Standard].self, from: data) {
            recentStandards = decoded
        }
    }

    private func persistRecent() {
        if let encoded = try? JSONEncoder().encode(recentStandards) {
            UserDefaults.standard.set(encoded, forKey: recentStorageKey)
        }
    }

    // MARK: - Favorites

    private func loadLocalFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesStorageKey),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            let ids = Set(decoded)
            for i in standards.indices {
                standards[i].isFavorite = ids.contains(standards[i].id)
            }
        }
    }

    private func persistFavorites() {
        let ids = standards.filter(\.isFavorite).map(\.id)
        if let encoded = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(encoded, forKey: favoritesStorageKey)
        }
    }

    // MARK: - Derived

    private func recomputeDerived() {
        favoriteStandards = standards.filter(\.isFavorite)
    }

    // MARK: - Helpers

    func standard(for id: UUID) -> Standard? {
        standards.first { $0.id == id }
    }

    func relatedStandards(for standard: Standard) -> [Standard] {
        standard.relatedStandardIds.compactMap { id in
            standards.first { $0.id == id }
        }
    }

    // MARK: - Mock Data Safe Access

    /// Access MockData.standards with a safety wrapper.
    /// Note: SIGTRAP crashes in static init cannot be caught — this is a best-effort fallback.
    private static func safeMockStandards() -> [Standard] {
        let novaId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID()
        let now = Date()

        return [
            Standard(
                id: UUID(uuidString: "BBBBBBBB-0001-0000-0000-000000000001") ?? UUID(),
                title: "SOP-001: Submitting a Ticket to Maui",
                category: .playbooks,
                content: """
# CHEAT-SOP-001: Submitting a Ticket to Maui

**For:** All agents | **Full SOP:** `docs/SOP/SOP-001-SUBMITTING-TICKETS.md`

---

## What Your Ticket Needs

- **Title** — one line, 80 chars max
- **Type** — `feature` | `bugfix` | `script` | `data_pipeline` | `research` | `refactor`
- **Priority** — `critical` | `high` | `normal` | `low`
- **Description** — what needs to be built or fixed
- **Acceptance Criteria** — at least 2 checkable conditions that prove it's done

---

## Where the Template Lives

```
~/.openclaw/workspace/tickets/TEMPLATE.md
```

Copy it. Name your file: `TICKET-NNN-short-name.md`
Drop it in: `~/.openclaw/workspace/tickets/`

---

## NATS Subjects

| Direction | Subject |
|-----------|---------|
| New ticket → Maui | Drop file + Aloha fires `service-requests.created` |
| Maui claims it | `service-requests.claimed` |
| Progress updates | `service-requests.progress` |
| Direct message to Maui | `agents.maui.query` |

---

## What Happens Next

1. Aloha detects new ticket file → notifies Maui via NATS
2. Maui reads it and opens a Stage 2 review conversation with you
3. You confirm scope → Stage 3 approval (you say yes before any code starts)
4. Maui writes a pre-work doc, then executes
5. Maui notifies you when done → you test → you sign off → Aloha closes it

---

**Key Rule: No sign-off from you = ticket stays open. Aloha does not close without confirmation.**
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["tickets", "workflow", "maui", "sop"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),

            Standard(
                id: UUID(uuidString: "BBBBBBBB-0002-0000-0000-000000000001") ?? UUID(),
                title: "SOP-002: Maui's Engineering Workflow",
                category: .playbooks,
                content: """
# CHEAT-SOP-002: Maui's Engineering Workflow

**For:** Maui (primary) + anyone tracking a ticket | **Full SOP:** `docs/SOP/SOP-ENGINEERING-TICKET-WORKFLOW.md`

---

## The 6-Stage Flow

```
[1] TICKET CREATED ──▶ [2] MAUI REVIEWS ──▶ [3] REQUESTER APPROVES
                                                       │
                              ┌────────────────────────┘
                              ▼
                      [4] MAUI DOCUMENTS INTENT
                              │
                              ▼
                          [5] EXECUTE
                              │
                              ▼
                      [6] SIGN-OFF → CLOSED
```

---

## One Line Per Stage

| Stage | Who Acts | Output |
|-------|----------|--------|
| 1 — Ticket Created | Requester | File at `~/.openclaw/workspace/tickets/TICKET-NNN.md` |
| 2 — Maui Reviews | Maui + Requester | Questions answered, scope confirmed |
| 3 — Approach Approved | Requester | Explicit go-ahead (NATS or direct) |
| 4 — Pre-Work Doc | Maui | `~/.openclaw/workspace-maui/docs/WORK-TICKET-NNN.md` |
| 5 — Execute | Maui | Code + progress updates via NATS |
| 6 — Sign-Off | Requester | Confirms done → Aloha closes + archives |

---

## Key Rule

> **No code before Stage 3 approval. No exceptions.**

---

## NATS Subjects (Progress Updates)

| Event | Subject |
|-------|---------|
| Ticket detected | `service-requests.created` (Aloha publishes) |
| Maui claims ticket | `service-requests.claimed` |
| Progress (25/50/75/100%) | `service-requests.progress` |
| Reach Maui directly | `agents.maui.query` |

---

**Stalled ticket?** Aloha pings if any stage sits >24h without movement. Escalates to Shaka after 48h at `todo`.
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["engineering", "maui", "workflow", "sop"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),

            Standard(
                id: UUID(uuidString: "BBBBBBBB-0003-0000-0000-000000000001") ?? UUID(),
                title: "Ticket Lifecycle: Visual Reference",
                category: .runbooks,
                content: """
# CHEAT: Ticket Lifecycle

**For:** Everyone | Visual reference for the full journey of any engineering ticket.

---

## Full Lifecycle

```
REQUESTER                 MAUI                    ALOHA

Creates ticket            ·                       ·
TICKET-NNN.md  ─────────────────────────────▶  Detects file
                          ·                    Fires NATS →
                          ◀────────────────────────────────
                  Stage 2: Reviews ticket
                  Asks clarifying questions ──▶
Answers questions ◀──────

Stage 3: APPROVAL ───────▶ Maui gets go-ahead
(sign-off #1)              No code until this happens

                          Stage 4: Writes pre-work doc
                          WORK-TICKET-NNN.md

                          Stage 5: Executes work
                          Progress via NATS (25/50/75/100%)

                  "Done. Please review." ───────────────▶
Reviews + tests ◀──────────────────────────────────────

Stage 6: SIGN-OFF ───────────────────────────▶ Aloha closes
(sign-off #2)                                  Archives ticket
                                               Work doc = perm record
```

---

## Status Flow

```
todo → in-review → approved → in-progress → done
                                           (or cancelled)
```

---

## Sign-Off Requirements

| # | Who Signs | What They're Approving |
|---|-----------|------------------------|
| 1 | Requester | Maui's proposed approach (Stage 3) |
| 2 | Requester | Completed deliverable (Stage 6) |

**Aloha will not close a ticket without sign-off #2 confirmed.**
""",
                authorId: novaId,
                authorName: "Nova",
                tags: ["tickets", "lifecycle", "workflow", "reference"],
                version: 1,
                createdAt: now,
                updatedAt: now,
                isFavorite: false
            ),
        ]
    }
}
