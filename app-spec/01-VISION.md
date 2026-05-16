# pod — The Team Pod
## Full Product Specification

> "Where the pod comes together."

---

## 1. Concept & Vision

**pod** is the native Apple intelligence platform for high-performance teams running AI agents. It replaces the fragmented stack — scattered chats, disconnected project boards, tribal knowledge, and terminal-based agent management — with one beautifully designed, deeply integrated app that runs on every device you own.

Where ORCA MC is the backend engine room, **pod** is the bridge. A real-time, always-aware command center that brings the entire team — Captain, Shaka, Maui, Chief, and every future agent — into one coherent experience across iPhone, iPad, Apple Watch, and Mac.

**Core feeling:** Confident control. Your team at a glance. Every agent humming. Nothing slipping through the cracks.

---

## 2. Design Language

### Aesthetic Direction
**"Obsidian & Electric"** — Dark, professional foundation with surgical use of color for signal over noise. Inspired by Bloomberg Terminal meets Linear meets Apple Newsroom. Dense information without clutter.

### Color Palette
```
Background Primary:    #0A0A0F  (near-black, true dark mode base)
Background Secondary: #141419  (card surfaces)
Background Tertiary:  #1C1C24  (elevated surfaces, sheets)

Accent Electric:     #3B82F6  (primary actions, links, highlights)
Accent Success:      #22C55E  (agents online, tasks done)
Accent Warning:      #F59E0B  (pending, attention needed)
Accent Danger:       #EF4444  (blockers, errors)
Accent Agent:        #A855F7  (agent-specific UI, purple for AI)
Accent Captain:       #F97316  (Captain's brand color, orange)

Text Primary:        #F8FAFC  (headings, important text)
Text Secondary:      #94A3B8  (body, descriptions)
Text Tertiary:       #475569  (timestamps, metadata)
Text Muted:          #2D3748  (disabled, placeholders)

Border:              #1E293B  (subtle separators)
Border Active:       #334155  (focused inputs, selected items)

Status Online:       #22C55E
Status Busy:         #F59E0B
Status Offline:      #475569
```

### Typography
```
Display:    SF Pro Display    Bold    34pt  (screen titles)
Title 1:    SF Pro Display    Bold    28pt  (section headers)
Title 2:    SF Pro Display    Semibold 22pt  (card titles)
Title 3:    SF Pro Text       Semibold 17pt  (list item titles)
Headline:   SF Pro Text       Medium  15pt  (emphasized body)
Body:       SF Pro Text       Regular 15pt  (standard text)
Caption:    SF Pro Text       Regular 13pt  (metadata, timestamps)
Label:      SF Pro Text       Medium  11pt  (badges, tags — uppercase tracking)
Mono:       SF Mono           Regular 13pt  (code, IDs, agent output)
```

### Spacing System (8pt Grid)
```
xxs:    4pt
xs:     8pt
sm:     12pt
md:     16pt
lg:     24pt
xl:     32pt
xxl:    48pt
xxxl:   64pt
```

### Motion Philosophy
- **Functional, not decorative** — animations communicate state changes, never delay the user
- Spring physics for interactive elements (bounce: 0.3, response: 0.4)
- 200ms ease-out for opacity transitions
- 150ms for micro-interactions (taps, toggles)
- Pull-to-refresh with haptic feedback
- Skeleton loading states, never spinners
- Watch: complication updates use subtle scale + fade

### Iconography
SF Symbols exclusively. Custom icons only for agent avatars.

---

## 3. Screen Inventory

### 3.1 Tab Bar (Root Navigation)
Five tabs, always visible:

| Tab | Icon | Label | Purpose |
|-----|------|-------|---------|
| Dashboard | `gauge.with.dots.needle.bottom.50percent` | pod | Real-time overview |
| Projects | `rectangle.3.group` | Projects | Boards & tasks |
| Chat | `bubble.left.and.bubble.right` | Chat | Team messaging |
| Knowledge | `books.vertical` | Knowledge | Standards & frameworks |
| Agents | `cpu` | Agents | Agent control center |

### 3.2 Dashboard (pod Tab)

**Purpose:** At-a-glance team status. The first thing you see. Everything that needs attention, nothing that doesn't.

**Sections (top to bottom):**

**Header:**
- Greeting: "Good morning, Captain" (time-aware)
- Date: "Sunday, March 22"
- Organization name badge
- Settings gear icon (top-right)

**Agent Status Strip** (horizontal scroll):
- Each agent as a card: avatar, name, status dot, last activity
- Tap → Agent detail sheet
- Color-coded: green (working), amber (idle), red (error), gray (offline)

**This Morning** (timeline):
- Filtered activity feed: last 12 hours
- Each item: icon + description + timestamp + actor
- Grouped by hour
- Types: task completed, message sent, agent milestone, approval requested

**Needs Attention** (red section):
- Blocked tasks
- Pending approvals
- Agent errors
- Empty state if nothing: "All clear. Your team is humming."

**Quick Actions** (4-icon grid):
- New task
- New message
- Search
- Scan (future: camera-based input)

**Watch Widget Preview:**
- Shows 3 most important things right now
- Tap to expand on Watch

---

### 3.3 Projects Tab

**Purpose:** All boards, all tasks. The operational heartbeat.

**Sections:**

**Board Groups** (horizontal scroll of group cards):
- Group name + board count
- Progress bar (tasks done / total)
- Color accent per group
- Tap → Board Group detail

**My Tasks** (persistent top section):
- Tasks assigned to current user
- Sorted: overdue → due today → upcoming
- Swipe actions: done, defer, delegate
- Tap → Task detail

**All Boards** (vertical list):
- Grouped by Board Group
- Each board: name, task count, stage distribution (plan/dev/verify/test/done as colored dots), last activity
- Tap → Board detail
- Long-press → Board quick actions menu

**Board Detail View:**
- Kanban columns: Plan | Dev | Verify | Test | Done
- Each column: task cards stacked
- Drag-and-drop between columns (iPad/Mac priority; iPhone uses tap-to-move)
- Column header: name + count + collapse toggle
- FAB: Add task to this board
- Filter bar: assignee, tag, priority, search

**Task Detail View:**
- Title (editable inline)
- Description (rich text, markdown support)
- Assignee picker (human or agent)
- Status badge (tap to change stage)
- Due date
- Tags (tap to add/remove)
- Custom fields (dynamic based on board config)
- Dependencies (linked tasks)
- Activity log (comments, state changes)
- Attachments
- Subtasks (checkbox list)
- Action buttons: Archive, Delete (admin only)

---

### 3.4 Chat Tab

**Purpose:** Unified team messaging. Human conversations and agent broadcasts in one thread.

**Layout:**
- Channel list (left sidebar on iPad/Mac; bottom sheet on iPhone)
- Message thread (main area)

**Channel List:**
- Pinned channels at top
- Unread indicator (bold + dot)
- Channel icon + name + last message preview + timestamp
- Quick mute toggle (swipe)
- Create channel FAB

**Channel Types:**
- `#general` — Team-wide announcements
- `#projects/{name}` — Project-specific discussion (auto-created from board)
- `#agents/{name}` — Agent output channel (auto-updated by agents)
- `#research` — Research findings feed
- `#alerts` — System alerts and blockers
- `#chief-desk` — Trading desk (Chief's domain)

**Message Thread:**
- Message bubbles: user avatar + name + text + timestamp
- Agent messages: special purple left-border, agent avatar
- Markdown rendering (bold, code blocks, links)
- Code blocks: syntax highlighted, copy button
- Images: inline preview, tap to full-screen
- Reactions (tap-hold on message)
- Reply threads (tap on message → expand thread)
- Agent @mentions highlight in purple

**Compose Bar:**
- Text input (expandable)
- Attach button (image/file)
- Agent mention button (`@`)
- Send button
- Voice input (future)

**Watch:**
- Inbox view: last 10 messages across all channels
- Tap message → dictation reply
- Complications: unread count badge

---

### 3.5 Knowledge Tab

**Purpose:** The team's brain. Standards, frameworks, and institutional knowledge, organized and searchable.

**Sections:**

**Quick Search** (top, always visible):
- Full-text search across all standards
- Recent searches
- Voice search (future)

**Browse by Category** (grid of category cards):
- Standards (e.g., "API Design", "Code Review", "Incident Response")
- Frameworks (e.g., "RFC Process", "Onboarding", "Architecture Decision Records")
- Playbooks (e.g., "Runbook: Database Backup", "Deployment Checklist")
- Each card: icon + name + item count

**Recent & Favorites**:
- Recently viewed standards
- Starred/favorited items
- Continue reading position (sync across devices)

**Standard Detail View:**
- Title + category badge
- Author + last updated
- Rich text content (markdown)
- Table of contents (auto-generated from headings)
- Related standards (linked)
- "Ask an Agent" button — sends to Chief/Maui for clarification
- Version history

**Create/Edit Standard:**
- Title input
- Category picker
- Rich text editor (markdown)
- Link to related standards
- Publish / Save Draft

**Agent Integration:**
- Agents can post summaries to Knowledge
- "Chief's Market Brief" auto-posts to #research, summary lands in Knowledge
- Auto-tagging by agent on post

---

### 3.6 Agents Tab

**Purpose:** The agent control center. See every agent, talk to any agent, understand what they're doing.

**Sections:**

**Agent Roster** (vertical list of agent cards):
- Each card: avatar, name, role label, status dot, current task
- Online/Offline toggle per agent
- Health indicator (good/warning/error)

**Agent Card Detail (tap):**
- Agent name + role
- Status: Online/Offline/Busy
- Current task description
- Recent activity (last 10 actions)
- "Send Message" — opens DM thread
- "View Logs" — real-time log stream
- "Pause Agent" toggle
- "Restart Agent" (confirmation required)
- "Configure" — agent-specific settings sheet

**Agent-to-Agent Chat:**
- Direct message any agent
- Group chat with multiple agents
- Same UI as team chat

**Agent Configuration:**
- Per-agent settings (skill packs, behavior params)
- Only for admin users

**Watch:**
- Agent status list (compact)
- Tap agent → dictation to send message
- Complication: agent count online/offline

---

### 3.7 Watch App

**Dedicated watchOS app with:**

**Main Screen (Agent Status):**
- Agent count: "4 online · 1 offline"
- List of agents with status dots
- Tap agent → quick message (dictation)

**Notifications:**
- Task assigned to you
- Approval requested
- Agent error detected
- Mentioned in chat

**Complications:**
- Modular: Agent count
- Circular: Status dot
- Rectangular: Last alert preview
- Corner: Unread message count

**Live Activities:**
- Active task progress
- Agent working indicator

---

### 3.8 Settings & Profile

**Profile:**
- Name, avatar, role
- Notification preferences (per-channel, per-event)
- Appearance: Dark/Light/System (default: Dark)

**Organization:**
- Org name, logo
- Member list
- Invite new member

**Integrations:**
- Apple Health (future)
- Calendar (future)
- Siri shortcuts

**Agent Preferences:**
- Which agents to show on Dashboard
- Notification thresholds

**About:**
- Version, licenses
- OpenClaw gateway status
- Debug: view raw API responses (hidden setting)

---

## 4. Data Model

### App Client Models (SwiftData)

```swift
// User-facing team member (mirrors ORCA MC User)
struct TeamMember {
    id: UUID
    name: String
    email: String
    preferredName: String
    role: MemberRole  // .owner, .admin, .member
    isAgent: Bool
    agentId: String?  // links to agent ID if isAgent
    avatarColor: String
    timezone: String
}

// Projects & Tasks
struct Project {
    id: UUID
    name: String
    description: String
    boardGroupId: UUID
    status: ProjectStatus
    stage: ProjectStage  // .plan, .dev, .verify, .test, .done
    createdAt: Date
    updatedAt: Date
    taskCount: Int
    completedTaskCount: Int
}

struct Task {
    id: UUID
    projectId: UUID
    title: String
    description: String
    status: TaskStatus
    stage: TaskStage
    assigneeId: UUID?
    dueDate: Date?
    priority: Priority  // .low, .medium, .high, .critical
    tags: [Tag]
    customFields: [CustomFieldValue]
    createdAt: Date
    updatedAt: Date
}

// Chat
struct Channel {
    id: UUID
    name: String
    type: ChannelType  // .general, .project, .agent, .research, .alerts
    description: String
    isPinned: Bool
    unreadCount: Int
    lastMessage: Message?
}

struct Message {
    id: UUID
    channelId: UUID
    authorId: UUID
    content: String
    timestamp: Date
    isAgent: Bool
    agentId: String?
    reactions: [Reaction]
    threadCount: Int
}

// Knowledge
struct Standard {
    id: UUID
    title: String
    category: StandardCategory
    content: String  // markdown
    authorId: UUID
    tags: [String]
    version: Int
    createdAt: Date
    updatedAt: Date
    isFavorite: Bool
    readingPosition: Int?  // character offset for continue-reading
}

// Agents
struct Agent {
    id: UUID
    name: String
    role: String  // "Head of Engineering", "Trading Bot"
    status: AgentStatus  // .online, .busy, .idle, .offline, .error
    currentTask: String?
    lastActivity: Date
    skills: [String]
    avatarColor: String
}
```

---

## 5. Architecture

### Platform Strategy
```
iOS App (Primary)     → iOS 17+, iPhone + iPad
watchOS App (Companion) → watchOS 10+, Apple Watch
macOS App (Future)    → macOS 14+, Mac
Widgets               → iOS 17+ widget kit
```

### App Architecture (MVVM + Clean Architecture)
```
Presentation Layer
├── Views (SwiftUI)
├── ViewModels (@Observable)
└── ViewState (enum-driven state management)

Domain Layer
├── UseCases (business logic)
├── Entities (domain models)
└── Repository Protocols

Data Layer
├── Repositories (implementations)
├── RemoteDataSource (ORCA MC API)
├── LocalDataSource (SwiftData offline cache)
└── DTOs (network response models)
```

### Backend Connection
```
pod iOS App
    │
    ├── REST API ──────────→ ORCA MC Backend (:8000)
    │                           ├── /api/v1/chat/*
    │                           ├── /api/v1/boards/*
    │                           ├── /api/v1/tasks/*
    │                           ├── /api/v1/users/*
    │                           └── /api/v1/agents/*
    │
    ├── WebSocket ─────────→ ORCA MC Backend (SSE/WS)
    │                           └── Real-time: messages, task updates, agent status
    │
    └── NATS ───────────────→ OpenClaw Gateway (future)
                                └── Agent-to-agent, agent broadcasts
```

### Local Storage (SwiftData)
- **Offline-first**: All data cached locally, synced on connectivity
- **Conflict resolution**: Server wins for tasks; merge for drafts
- **Agent state**: Cached for offline Dashboard view

### Real-time Sync
- SSE (Server-Sent Events) for message delivery
- Poll-based refresh for Dashboard (30s interval)
- Agent status via WebSocket (immediate)
- Background app refresh for notification badges

---

## 6. API Integration (ORCA MC)

### Authentication
```
POST /api/v1/auth/login
Body: { "token": "<see $ORCA_BEARER_TOKEN — ~/.openclaw/secrets/env.sh per Phase 2.1>" }
Response: { "user": {...}, "token": "...", "organization": {...} }
```

### Key Endpoints
```
GET  /api/v1/users/me                      → Current user profile
GET  /api/v1/chat/channels                 → All channels
GET  /api/v1/chat/channels/{id}/messages  → Channel messages
POST /api/v1/chat/channels/{id}/messages   → Send message
GET  /api/v1/boards                        → All boards
GET  /api/v1/boards/{id}/tasks            → Board tasks
POST /api/v1/tasks                         → Create task
PATCH /api/v1/tasks/{id}                  → Update task
GET  /api/v1/agents                        → All agents
GET  /api/v1/agents/{id}/status           → Agent status
GET  /api/v1/healthz                       → Server health
```

### Real-time (SSE)
```
GET /api/v1/events/stream
Headers: Authorization: Bearer {token}
Events: message.new, task.updated, agent.status, approval.requested
```

---

## 7. Technical Decisions

### Stack
| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| State | @Observable + SwiftData |
| Networking | async/await + URLSession |
| Real-time | Server-Sent Events (URLSessionStreamTask) |
| Local DB | SwiftData |
| DI | Environment values (native SwiftUI) |
| Icons | SF Symbols |
| Animations | SwiftUI transitions + spring |

### Package Manager
Swift Package Manager (no CocoaPods/Carthage needed)

### Key Dependencies
```swift
// Networking
// (native URLSession — no external HTTP client needed)

// Markdown rendering
MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui)

// Syntax highlighting (for code blocks in chat)
Highlightr (https://github.com/raspu/Highlightr)

// Date formatting
// (native DateFormatter / RelativeDateTimeFormatter)

// Rich text editor
// (native TextEditor + custom toolbar)
```

### Project Structure
```
pod/
├── App/
│   ├── podApp.swift
│   └── AppState.swift
├── Core/
│   ├── Design/
│   │   ├── Theme.swift
│   │   ├── Colors.swift
│   │   └── Typography.swift
│   ├── Extensions/
│   ├── Utilities/
│   └── Haptics.swift
├── Data/
│   ├── Remote/
│   │   ├── APIClient.swift
│   │   ├── Endpoints.swift
│   │   ├── DTOs/
│   │   └── SSEClient.swift
│   ├── Local/
│   │   └── SwiftDataModels.swift
│   └── Repositories/
├── Domain/
│   ├── Entities/
│   ├── UseCases/
│   └── Protocols/
├── Presentation/
│   ├── Shared/
│   │   ├── Components/
│   │   ├── Sheets/
│   │   └── State/
│   └── Features/
│       ├── Dashboard/
│       ├── Projects/
│       ├── Chat/
│       ├── Knowledge/
│       └── Agents/
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings
```

---

## 8. Watch App Architecture

```
podWatch/
├── podWatchApp.swift
├── ContentView.swift
├── AgentStatusView.swift
├── MessageReplyView.swift
├── Complication/
└── NotificationController/
```

**Strategy:** Watch app is a lightweight companion. It reads data from the same ORCA MC API but does NOT write. Write actions (messages, task updates) use iPhone as relay via WatchConnectivity.

---

## 9. Phase Plan

### Phase 0 — NATS Security Hardening (PRIORITY)
- [ ] Token-based auth per agent identity
- [ ] TLS on NATS connection (100.83.183.42:4222)
- [ ] Rate limiting per agent
- [ ] Security review before production

### Phase 1 — Foundation ✅ (COMPLETED)
- [x] Project setup (XcodeGen)
- [x] Design system (Theme, Colors, Typography)
- [x] ORCA MC API client
- [x] Authentication flow
- [x] Dashboard screen

### Phase 2 — Core Experience ✅ (COMPLETED)
- [x] Chat tab (channels + messages + compose)
- [x] Projects tab (boards + tasks)
- [x] Agent status strip on Dashboard
- [x] Real-time message delivery (SSE)
- [x] Offline persistence (SwiftData)

### Phase 3 — Watch + Ambient Mode ✅ (IN PROGRESS)
- [x] watchOS app
- [x] Agent status complications
- [x] Message notifications + reply
- [x] **Ambient Wall Display Mode** (see Section 11)
- [x] Siri shortcuts (App Intents)
- [x] Home screen widgets
- [ ] Live Activities

### Phase 4 — Onboarding + Polish
- [ ] Onboarding flow (token entry, feature tour)
- [ ] Push notification pipeline (APNs)
- [ ] Real-time flow diagrams (end-to-end sequence)
- [ ] Orca migration acceptance criteria

### Phase 5 — Agent Task Chains
- [ ] Multi-step workflow across agents
- [ ] Chain visualization (who → who → done)
- [ ] Blocked chain indicators
- [ ] Chain assignment UI

### Phase 6 — Polish
- [ ] Widgets refinement
- [ ] Background refresh
- [ ] iPad optimization (split view, stage manager)
- [ ] Accessibility audit

---

## 10. Open Questions — RESOLVED

| Question | Decision |
|----------|----------|
| Standards data model | **New `standards` table** in ORCA MC, separate from boards |
| Agent identity | **User with isAgent flag** — single query, clean display |
| Real-time transport | SSE at `/api/v1/events/stream` — needs backend verification |
| Push notifications | Build into ORCA MC backend (APNs) |
| Watch hardware | Later phase — iPad/iPhone MVP first |

---

## 11. New Features (Post-Review Additions)

### 11.1 Ambient Wall Display Mode

*Added per Aurora's recommendation — the killer feature for always-on team awareness.*

A dedicated always-on mode for iPad wall-mounted displays. No interaction needed, just team status at a glance.

**Layout:**
- Organization name + time (top)
- Agent status strip (horizontal scroll, auto-updates via SSE)
- Activity feed (scrolling, color-coded by type)
- Attention indicator (bottom, pulses red if blocked tasks exist)

**Behavior:**
- Auto-dim after 5 minutes (brightness → 30%)
- Wake on tap
- No authentication required (dedicated device account)
- Landscape-only, full-screen, status bar hidden
- Exit via swipe-down gesture

**Tech:** UIScreen.main.brightness, SSE subscription, no polling.

### 11.2 Agent Task Chains

*Added per Captain's "go big" directive.*

Multi-step workflows assigned across multiple agents. Visual chain shows progress through stages.

**Model:**
```swift
struct TaskChain {
    let id: UUID
    var title: String
    var steps: [ChainStep]
    var status: ChainStatus  // .active, .blocked, .completed
}

struct ChainStep {
    let id: UUID
    var assignedAgentId: UUID
    var taskId: UUID
    var status: StepStatus  // .pending, .inProgress, .done
    var blockedBy: [UUID]  // step IDs this depends on
}
```

**UI:** Horizontal chain with connected step nodes. Each node shows agent avatar + task status. Blocked steps glow red. Completed steps show checkmark. Tap any node to see task details.

### 11.3 Real-Time Architecture

*Added per Aurora's review — end-to-end flow documentation.*

**Chief Alert → Shaka's iPhone (< 200ms):**

```
1. Chief publishes to NATS
   NATS: agents.chief.alerts { alert_data }

2. Bridge picks up message
   Bridge: parse → transform to APNs payload

3. Bridge calls ORCA MC push endpoint
   POST /api/v1/push/send
   Body: { device_tokens: [...], payload: {...} }

4. ORCA MC sends to APNs
   APNs → Shaka's iPhone

5. pod receives notification
   UserNotificationCenter → handleNotification()

6. App routes to correct screen
   NotificationRouter.route() → .approvals
```

**Agent Status → Dashboard (< 1s):**

```
1. Agent publishes status to NATS
   NATS: agents.{name}/status { online, task }

2. Bridge picks up → ORCA MC
   POST /api/v1/agents/{id}/status

3. ORCA MC broadcasts via SSE
   SSE → pod SSEClient

4. pod updates Dashboard in real-time
   onAgentStatusUpdate() → @Observable agent list
```

---

## 12. NATS Security

*Added per Aurora's review — Phase 0 priority.*

Current state: NATS at 100.83.183.42:4222 with no auth, no TLS.

**Required hardening (Phase 0, before production):**

1. **Token-based auth:** Each agent gets a unique JWT token. NATS verifies token on connect. No token = no connection.

2. **TLS:** All NATS connections must use TLS 1.2+. Non-TLS connections rejected.

3. **Rate limiting:** Per-agent message rate limits to prevent abuse.

4. **Audit logging:** All NATS publishes logged with agent identity + timestamp.

**Implementation:**
- Use NATS nkeys or JWT-based auth
- TLS via certs (Let's Encrypt or self-signed internal CA)
- nginx or NATS built-in rate limiting

---

## 13. Onboarding Flow

*Added as Phase 4 item — critical for first-time users.*

**4-step onboarding:**

1. **Welcome** — "Where the pod comes together." tagline, feature preview cards
2. **Connect** — Token entry field, validates against ORCA MC `/api/v1/users/me`
3. **Permissions** — Push notification authorization request, local network access
4. **Ready** — Welcome message with user name, "Get Started" → ContentView

Token stored in Keychain. Onboarding shown once per install, skipped if token already present.

---

*Specification version 1.1 — March 22, 2026*
*Authors: Captain, Shaka, Maui*
*Review: Aurora (Architecture)*
