# DDS: pod App Simulator Automation and Auth Cleanup
**Author:** Maui 🪝 | **Date:** 2026-04-03 | **Status:** EXECUTING

---

## Goal

Make `pod` honest again:
1. remove fake/demo chat and simulator auth bypasses
2. restore a single real token-based auth flow
3. add a real automation path for navigation testing
4. use Simulator for smoke tests and connected iPad for truth

---

## Problem

The current app is half real and half demo:
- simulator builds auto-authenticate
- token submission can bypass backend verification
- chat channels/messages are hardcoded in simulator
- typing indicators are simulated
- navigation appears to work, but much of it is staged rather than real

This helped prove UI shape, but it blocks us from trusting auth, routing, and message behavior.

---

## Constraints

### 1) Peekaboo is useful, but not sufficient
Peekaboo can:
- inspect the Mac desktop
- control Xcode, Simulator.app, dialogs, windows, menus
- read logs and UI state on macOS

Peekaboo cannot be trusted as the primary way to generate iOS touch events inside the Simulator framebuffer.

### 2) Camera gives us second-source truth
A Logitech C922x pointed at the Simulator now, and later at the connected iPad, lets us visually confirm what the device is doing.

### 3) The right automation layer is XCUITest
For reliable app interaction, we should use native Apple UI automation rather than coordinate-click hacks.

---

## Decision

We will use a two-track approach.

### Track A — Cleanup
Remove all simulator-only fake auth/chat behavior from the app runtime.

### Track B — Automation
Add a minimal XCUITest smoke suite for:
- launch
- token entry
- connect tap
- post-auth landing
- basic tab navigation

Peekaboo remains the Mac-side observer/controller. XCUITest becomes the iOS-side finger.

---

## Scope

### In scope
- remove simulator auth bypasses
- remove demo chat data injection from runtime chat flows
- remove simulator-only fake navigation shortcuts
- document current auth path and failure points
- add a minimal UI test target if missing
- create 2-3 smoke UI tests

### Out of scope
- full end-to-end messaging reliability
- broad UI test coverage for every screen
- replacing all mock data in unrelated dashboards/projects views

---

## Phases

### Phase 1 — Runtime honesty
Target files likely include:
- `Sources/App/AppState.swift`
- `Sources/App/ContentView.swift`
- `Sources/App/podApp.swift`
- `Sources/Presentation/Features/Chat/ChatViewModel.swift`
- `Sources/Presentation/Features/Chat/ChatView.swift`

Actions:
- remove simulator instant-auth paths
- remove auto-login hacks intended only for demo
- remove hardcoded simulator channel/message lists from runtime chat flow
- stop simulated typing behavior in chat runtime
- keep backend/proxy diagnostics where useful, but do not treat them as success

### Phase 2 — Auth truth
- define one token submission path
- verify backend reachability
- verify token against backend
- persist token only on success
- surface real errors clearly

### Phase 3 — UI automation
If no UI test target exists:
- add `podUITests`
- add smoke tests for connect + navigation

Initial smoke tests:
1. app launches to auth screen
2. token can be entered and connect tapped
3. authenticated user lands in the main shell
4. tab navigation works

### Phase 4 — Real-device validation
- run on connected iPad
- observe with camera + Xcode logs
- confirm token flow and navigation on actual hardware

---

## Success criteria

- [ ] app no longer auto-authenticates in simulator
- [ ] token flow only succeeds on real backend validation
- [ ] chat no longer shows fake simulator messages/channels
- [ ] basic navigation can be exercised by UI tests
- [ ] connected iPad can run the same auth flow honestly

---

## Risks

### Risk: Removing demo paths makes the app feel more broken before it gets better
Mitigation: do cleanup in small passes and keep each pass buildable.

### Risk: Backend/proxy assumptions are still wrong
Mitigation: keep diagnostics visible and test against the connected iPad as soon as possible.

### Risk: No existing UI test target
Mitigation: create a minimal one instead of overengineering.

---

## Immediate next actions

1. remove fake auth and fake chat from runtime path
2. inspect `pod.xcodeproj` for a missing UI test target
3. add minimal smoke automation plan
4. build and validate the app again
