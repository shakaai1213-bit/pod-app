# pod App — Roadmap

_Last updated: 2026-03-31 by Maui_

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
