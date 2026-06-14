# pod App — Roadmap

_Last updated: 2026-05-24 by codex-maui-arm_

---

## 2026-05-24 Maui Arm Upgrade Addendum — Super Round

Pod is now the ORCA cockpit, not just the original chat/projects app. The next upgrade round should focus on one reusable review workflow across all agent-proposed work:

`ORCA truth -> agent proposal -> Pod review card -> Tony accept/edit/drop/defer -> ORCA evidence`

### Priority 1 — Shared Review UI Pattern
- [ ] Create one reusable proposed-item/review-card pattern for accept, edit, drop, defer, open trace, and artifact checksum.
- [ ] Use the same pattern for Project milestones, Memory candidates, Schoolhouse suggestions, approval rows, and workspace tool requests.
- [ ] Show provenance on every card: route/model, agent run id, artifact hash, created time, reviewer gate.

### Priority 2 — Project Automation Surface
- [ ] Add Proposed Milestones panel to project detail.
- [ ] Show Mermaid V2 generation run, artifact, route, and proposed milestone metadata.
- [ ] Support accept/edit/drop and gated advance to Scoping.

### Priority 3 — Memory Review Queue
- [ ] Add Memory Queue inside Knowledge first.
- [ ] Group candidates by safe, sensitive, deferred, rejected, and committed.
- [ ] Show source, duplicate risk, Chroma target, reviewers required, and approve/reject/defer actions.

### Priority 4 — Schoolhouse Suggestions
- [ ] Add Today's Suggestions above Pod Chat or in Work.
- [ ] Cap visible suggestions and expose detector, confidence, linked tickets/projects, and proposed action.
- [ ] Never auto-mutate; every action requires Tony tap.

### Priority 5 — Chat Continuity
- [ ] Keep live inbox ack/async model honest for all six active agents.
- [ ] Show sent -> accepted -> claimed -> replied -> stale/failed states.
- [ ] Append live replies only when ORCA returns live-inbox provenance.

### Priority 6 — Ticket Cockpit Polish
- [ ] Preserve the approval/sign buttons and full-detail traverse path.
- [ ] Make Needs Your Sign -> Detail -> Trace/Evidence -> Approve/Pass/Request Review the primary flow.
- [ ] Move deeper exports/integrity tools behind a Tools menu.

### Priority 7 — Personal Device Safety
- [ ] Add Settings privacy panel: backend, account, token storage, push content mode, granted permissions, and "what agents can see."
- [ ] Default push notifications to private content.
- [ ] Avoid Contacts/Photos/Location permissions unless a feature explicitly needs them.

### Theme Breakdown To Completion

#### Theme A — One Review Muscle Memory
- [x] A1 Review data model: title, body, status, provenance, artifact hash, trace id, required reviewers, available actions.
- [x] A2 Shared review card: one SwiftUI card/list row with status, provenance, action buttons, and trace affordance.
- [x] A3 Action adapters: feature-specific ORCA endpoint calls behind one UI action shape.
- [x] A4 First production use: replace one narrow approval/tool-request flow without losing current behavior.
- [x] A5 Promote pattern: reuse card for Project Automation, Memory Queue, and Suggestions.

#### Theme B — Project Automation
- [x] B1 Decode proposed milestones, automation flags, and last generation run id.
- [x] B2 Add Generate Milestones action with pending/running/failure state.
- [x] B3 Show Proposed Milestones panel with run id, artifact hash, route/model, dependencies, and status.
- [ ] B4 Wire accept/edit/drop. Accept/drop are wired; edit still needs a first-class ORCA/UI path.
- [x] B5 Gate Advance to Scoping on resolved proposals and durable milestones.

#### Theme C — Memory Review
- [x] C1 Add Memory Queue inside Knowledge.
- [ ] C2 Group safe, sensitive, deferred, rejected, and committed candidates.
- [x] C3 Show source, extracted claim, Chroma/agent-memory target, provenance, and reviewers. Duplicate-risk display still depends on ORCA payload.
- [x] C4 Wire approve/reject/defer through ORCA.
- [x] C5 Show promotion proof after commit where ORCA returns decision/proof fields.

#### Theme D — Schoolhouse Suggestions
- [x] D1 Add suggestion models with detector/source/provenance, linked refs, action, and status.
- [x] D2 Add capped Today's Suggestions panel in Work or above Direct Chat.
- [x] D3 Add create-ticket, defer/snooze, dismiss, and accept actions. Attach-to-existing remains future work.
- [ ] D4 Add grouping, age, confidence sorting, and stale/error states. Risk/age sorting and empty/error states are in; grouping and confidence display remain.
- [ ] D5 Complete seven-day stability proof before LIVE.

#### Theme E — Chat Continuity
- [ ] E1 Show sent -> ORCA accepted -> live inbox claimed -> reply appended -> stale/failed state per message.
- [ ] E2 Keep active channel SSE open where possible and expose reconnect state.
- [x] E3 Show agent capability badges for compute, live inbox, agent run, and tool request.
- [x] E4 Improve attached-ticket workspace drawer for files, artifacts, runs, approvals, and tools.
- [x] E5 Keep real tools approval-gated through ORCA workers, never Pod-local provider secrets.

#### Theme F — Ticket Cockpit
- [ ] F1 Preserve sign/pass buttons and scrollable detail traversal.
- [ ] F2 Make Needs Your Sign -> Detail -> Trace/Evidence -> Approve/Pass/Request Review the primary lane.
- [ ] F3 Move deep exports/integrity/backfill actions behind Tools.
- [ ] F4 Add short attention digest explaining why the ticket needs review.
- [ ] F5 Keep Tony and agent views aligned to the same ORCA truth.

#### Theme G — Work Home
- [ ] G1 Show waiting approvals, stale tickets, active runs, high-priority projects, and suggestions.
- [ ] G2 Add one-tap links into ticket, project, chat, and memory detail.
- [ ] G3 Keep safe priority edits with visible suggestion provenance.
- [ ] G4 Add last-updated/source freshness indicators.
- [ ] G5 Add cleared-today/still-waiting daily loop.

#### Theme H — Trust, Privacy, Device Readiness
- [x] H1 Add privacy panel with backend, account, token storage, push mode, permissions, and agent visibility.
- [ ] H2 Default notification previews to private content.
- [x] H3 Avoid Contacts/Photos/Location permissions unless explicitly needed.
- [ ] H4 Move toward Sign in with Apple/JWT refresh rather than broad shared-token patterns.
- [x] H5 Add plain agent-access explanation.

#### Theme I — Observability And Acceptance
- [x] I1 Add backend/SSE/live-inbox freshness chips where relevant.
- [ ] I2 Add simulator smoke checklists for project automation, memory, suggestions, chat, and ticket approval.
- [ ] I3 Expose ORCA trace proof for each completed flow.
- [ ] I4 Pair each Pod surface commit with DDS/catalog updates.
- [ ] I5 Produce final release bundle with commits, traces, residual risks, and rollback notes.

### Completion Definition
- [x] Shared review card is used by Project Automation, Memory Queue, and Suggestions.
- [ ] One project milestone flow is live-smoked end-to-end with ORCA trace evidence.
- [ ] One memory candidate is approved or rejected from Pod with provenance visible.
- [ ] One proactive suggestion is dismissed/deferred or converted to a ticket by Tony tap.
- [ ] One live-inbox message per active agent shows honest delivery state or clear failure.
- [ ] Ticket approval traversal remains usable and buttons remain available.
- [ ] Work shows the daily operator stack with freshness indicators.
- [x] Settings exposes personal-device privacy posture.
- [x] Pod builds cleanly and all touched flows have smoke evidence.
- [ ] Work log, DDS/catalog rows, residual risks, and rollback notes are recorded.

---

## ✅ Phase 1 — Foundation (Complete)
- [x] App shell, navigation, tab bar
- [x] Onboarding / token entry
- [x] Auth flow with network reachability check
- [x] Token storage in UserDefaults
- [x] App icons and branding
- [x] Design system (colors, typography, theme)
- [x] iPad + iPhone adaptive layout

## ✅ Phase 2 — Core Features (Complete)
- [x] Chat channels list + unread badges
- [x] Chat message list with timestamps
- [x] Compose bar + send messages
- [x] Pull-to-refresh on channel list
- [x] Message grouping (consecutive + date separators)
- [x] Channel mute/unmute
- [x] Agent status display on dashboard
- [x] Backend REST API — full CRUD for channels + messages
- [x] UserNameCache for author name resolution
- [x] iOS 26 Task.sleep workaround (`TaskSafeSleep`)
- [x] Chat polling fallback (5s interval)

---

## 🔲 Phase 3 — Real-Time & Polish (In Progress)

### 3.1 SSE Real-Time Events (BLOCKED — backend)
The app has `SSEClient.swift` with full event types and reconnection logic, but `establishConnection()` is a **stub** because the backend has no SSE endpoint.

**Backend needs:**
- `GET /api/v1/events/stream` — SSE endpoint emitting `message.new`, `task.updated`, `agent.status`, `approval.requested` events
- Requires backend changes by Captain/Tony

**App side (ready):**
- `SSEClient` with auto-reconnect, exponential backoff, event types
- `PushNotificationService` with rich categories (MESSAGE, TASK, APPROVAL, AGENT_ERROR)
- Notification routing via `NotificationAction`

**Once backend SSE is live:** Connect `ChatViewModel` to SSE stream, replace polling loop.

### 3.2 Push Notifications (Ready, needs backend support)
- `PushNotificationService` fully implemented
- Registers device token with backend via `POST /api/v1/push/register`
- Handles foreground + background notifications
- **Needs:** Backend APNS integration (NATS webhook → APNS push)

### 3.3 Reply Threading (Ready to implement)
- `Message.replyTo` field already exists in model
- `ComposeBar` has reply UI (replyingTo state)
- **Needs:** Backend support for `GET /api/v1/chat/channels/{id}/messages?reply_to={id}`
- **App side:** Add "View thread" button, thread view sheet

### 3.4 Agent Control Panel (Partially done)
- `AgentsView` + `AgentDetailSheet` + `LogStreamView` exist
- **Needs:** Backend `POST /api/v1/agents/{id}/invoke` endpoint
- Status cards + agent list already rendered from REST API

### 3.5 Projects / Board View ✅ (Complete)
- `ProjectsView`, `BoardDetailView`, `TaskDetailView`, `TaskDetailSheet` all exist
- `BoardRepository` + `ProjectsViewModel` fully wired to REST API (`GET /api/v1/boards`, `GET /api/v1/boards/{id}/tasks`)
- Falls back to mock data when backend unavailable
- Status filter, priority badges, assignee avatars, due date display all working

### 3.6 Knowledge / Standards ✅ (Complete)
- `KnowledgeView`, `StandardDetailView`, `StandardEditorView` wired to REST API (`GET /api/v1/standards`)
- `StandardRepository` fully implemented with CRUD operations
- Favorites and recent standards persisted to UserDefaults
- Category filtering and search working
- 4 standards live from backend (DDS Protocol, Code Review, API Design, RFC Process)

### 3.7 Agents View ✅ (Complete)
- `AgentsView`, `AgentDetailSheet`, `LogStreamView` wired to REST API (`GET /api/v1/agents`)
- Status cards + agent list rendered from REST API
- **Remaining:** `POST /api/v1/agents/{id}/invoke` for actual command invocation (blocked on backend)

---

## 🔲 Phase 4 — Polish & Launch

- [ ] Wall Display mode (launcher + modifier exist)
- [ ] Widget Extension (partially built — `podWidgetExtension/`)
- [ ] App Shortcuts / Siri integration (`AppShortcuts.swift` + `AppIntents.swift` exist)
- [ ] Loading states + skeleton views
- [ ] Error state views per feature
- [ ] Empty state views per feature
- [ ] Haptic feedback on send, reactions
- [ ] Dynamic Type support
- [ ] Dark/Light/System theme toggle
- [ ] Simulator proxy script for Mac Mini USB debugging

---

## 🔒 Blocked on Tony/Physical iPad
- Auth flow end-to-end testing (iOS 26 Task.sleep)
- Physical device push notification testing
- Real device on Tailscale VPN testing

## 🔒 Blocked on Captain/Backend
- SSE events endpoint (`/api/v1/events/stream`)
- APNS push relay (NATS → APNS)
- `POST /api/v1/agents/{id}/invoke` for agent control
- Reply thread query support
