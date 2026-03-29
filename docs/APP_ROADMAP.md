# Pod App Roadmap

> Last updated: 2026-03-28 by Maui

## Current Status: ✅ Phase 1 Complete — Live on Physical iPad

The app builds and runs on Tony's iPad via Tailscale. Key fixes deployed:
- Auth timeout: `DispatchSemaphore` (avoids iOS 26 `Task.sleep` bug)
- Backend URL: `http://100.76.196.40:8000` (Tailscale IP)
- App runs from Xcode (⌘R) — CLI installs crash due to DerivedData issues

---

## Phase 1: Core Fixes ✅
- [x] Auth timeout fix (DispatchSemaphore workaround)
- [x] Backend URL configurable via onboarding
- [x] Build succeeds on iPhone 17 Pro simulator
- [x] Live on physical iPad (Shaka's iPad, UDID: 00008030-0006644A0130C02E)
- [x] Timestamps in chat view (backend `created_at` → `Date`)
- [x] Agent status display on dashboard (name, role, status dot, last activity)
- [x] Pull-to-refresh on channel list and dashboard

---

## Phase 2: Agent Integration 🚧 In Progress
- [ ] Connect Maui agent to pod app (NATS or REST)
- [ ] Agent message threading (reply-to in chat)
- [ ] Agent task delegation (assign task from app)
- [ ] Real agent status from ORCA MC backend (not mock data)
- [x] Welcome message to #general on ORCA MC

---

## Phase 3: Polish
- [ ] Avatars (actual images, not just initials)
- [x] Unread message badges on channel list ✅
- [ ] Offline support (queue messages, show cached data)
- [x] Message reactions UI in place ✅ (need backend support)
- [ ] Activity feed from real backend events

---

## Phase 4: Production
- [ ] Crash reporting (Crashlytics / Sentry)
- [ ] App Store listing prep (screenshots, description, keywords)
- [ ] Code signing and provisioning profiles
- [ ] Push notifications (APNS)
- [ ] Privacy policy and terms of service

---

## Known Issues
- **iOS 26 Task.sleep bug**: `Task.sleep` unreliable in `withThrowingTaskGroup` — use `DispatchSemaphore` instead
- **DerivedData corruption**: Clean rebuild needed after certain installs — run from Xcode (⌘R)
- **UDID instability**: iPad shows different UDIDs across USB/WiFi reconnects
- **NATS wildcard subscriptions**: `fnmatch` pattern `">"` needs `"*"` replacement
- **Backend /api/v1/health**: Returns 404 (not implemented)

---

## Tech Stack
- **Framework**: SwiftUI + UIKit (WidgetKit for widgets)
- **Build**: XcodeGen (project.yml)
- **Architecture**: MVVM + Repository pattern
- **Local Storage**: SwiftData
- **Backend**: ORCA MC REST API (http://100.76.196.40:8000)
- **Push**: APNS via ORCA MC backend
- **Networking**: URLSession + async/await
