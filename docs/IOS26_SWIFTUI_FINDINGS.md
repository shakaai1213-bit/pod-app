# DDS — iOS 26 SwiftUI Findings (Starfish Sprint #1)

**Date:** 2026-03-31
**Author:** Starfish 🭐 (via Maui)
**Source:** `workspace-starfish/experiments/findings/ios26_swiftui.md`
**Confidence:** Medium (iOS 26 beta, March 2026)

---

## Key Issues

| Area | Severity | Finding |
|------|----------|---------|
| Background Tasks | 🔴 HIGH | `@SceneStorage` + `.background` phase unreliable. Replace with iOS 26 `Observations` AsyncSequence |
| Navigation | 🟡 MEDIUM | Liquid Glass auto-applies to TabViews (beta bug: accessory cutoff). Landscape safe area changed to 20pt top inset |
| Real-time Updates | 🟢 IMPROVEMENT | `Observations` AsyncSequence is *better* than old `objectWillChange` Combine |
| Async Networking | ✅ CLEAN | No iOS 26-specific issues |
| Authentication | ✅ CLEAN | No iOS 26-specific issues |

## Action Items for pod App

### HIGH — Do Now
- [ ] Replace any `@SceneStorage` + `.background` phase state saving with iOS 26 `Observations` AsyncSequence
- [ ] Check for hardcoded safe area values — switch to dynamic `.safeAreaInsets`

### MEDIUM — Next Sprint
- [ ] Audit TabView floating buttons — if using `.tabBarBottomAccessory`, switch to floating ZStack buttons with `.glassEffect`
- [ ] Monitor `NavigationStack` ecosystem for iOS 27 shifts

### CLEAN (No Action Needed)
- ✅ URLSession networking — no iOS 26 issues
- ✅ Auth header patterns — no iOS 26 issues
- ✅ Real-time state tracking — use `Observations` AsyncSequence (improvement!)

## Details

### 1. Liquid Glass TabView Redesign
- iOS 26/Xcode 26 auto-applies Liquid Glass to all TabViews
- **Beta bug:** `.tabBarBottomAccessory` buttons cut off when tab bar minimizes via `.tabBarMinimizeBehavior(.onScrollDown)`
- **Workaround:** Use floating ZStack buttons with `.glassEffect(.regular.interactive())` instead

### 2. Liquid Glass Overuse
- Apple explicitly: Liquid Glass elements should *never* be content — only sit on top
- Applying `.glassEffect()` to list rows or main content creates unusable UI
- **Workaround:** Reserve Liquid Glass for toolbars, tab bars, floating buttons only

### 3. @SceneStorage Background Unreliable (🔴)
- Pre-iOS 26: saving scene state on `.background` phase is unreliable
- Data can be lost on termination
- **Fix:** iOS 26 `Observations` AsyncSequence for transactional state change tracking

### 4. Observations Transaction Boundaries
- `Observations` starts transaction on first `willSet`, emits at next `await`
- Multiple synchronous mutations are batched into one emission
- **Design implication:** Rapid state changes may be coalesced

### 5. Landscape Safe Area: 20pt Top Inset (All iPhone 17)
- All iPhone 17 models now have 20pt top safe area in landscape
- **Fix:** Always use safe area insets dynamically — no hardcoded values

### 6. NavigationStack Stability
- `NavigationStack` + `NavigationPath` stable but ecosystem shifting
- Monitor for iOS 27 changes

### 7. Swift 6.2 + @Sendable
- `Observations` `@Sendable` closure requirements can cause compilation friction
- **Fix:** Mark closures as `@Sendable`, use `@MainActor` for UI observation

### 8. URLSchemeHandler AsyncSequence
- `URLSchemeHandler.reply` must return `some AsyncSequence<URLSchemeTaskResult>`
- **Fix:** Always call `continuation.finish()` in all code paths (success, error, missing URL)

---

## Sources

- Donny Wals — Liquid Glass Tab Bars iOS 26
- Donny Wals — Custom UI with Liquid Glass
- Use Your Loaf — Observations AsyncSequence
- Use Your Loaf — Custom URL Schemes
- Use Your Loaf — iPhone 17 Screen Sizes
- Swift.org — Swift 6.3 Released
- Swift Evolution SE-0475 — Transactional Observation
