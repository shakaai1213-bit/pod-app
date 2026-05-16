# pod — Auth Spec: Sign in with Apple → ORCA MC JWT

**Status:** All decisions locked — ready to build  
**Author:** Maui 🪝  
**Date:** 2026-05-03  
**Tier:** 4 — requires Captain sign-off before implementation  
**Prior research:** workspace-starfish/experiments/findings/mobile-app-auth.md (sprint 20, 2026-04-01)

---

## Problem

The pod app currently uses a single shared bearer token (`LOCAL_AUTH_TOKEN`) hardcoded in source. This token:
- Is identical across all clients (app, agents, scripts)
- Lives in source history and has been distributed via TestFlight builds
- Cannot be per-user or revoked individually
- Gives any holder full ORCA MC API access

## Solution

Sign in with Apple → backend exchanges Apple's identity token for a short-lived ORCA MC JWT → app stores JWT in Keychain.

Each user gets their own session token. Tokens expire in 30 minutes. Refresh tokens rotate on use. Compromise of one device doesn't affect other clients.

---

## What Changes

| Component | Current | After |
|-----------|---------|-------|
| `AppState.isAuthenticated` | Hardcoded `true` (demo mode) | Driven by Keychain token presence |
| `AppState.storeToken()` | `UserDefaults` | `KeychainSwift` |
| `AppState.authenticate()` | Manual token entry + verify | Removed — replaced by SIWA flow |
| `PushNotificationService.authToken` | Hardcoded bearer literal | JWT from `TokenStore` |
| Backend auth | Single shared `LOCAL_AUTH_TOKEN` | `LOCAL_AUTH_TOKEN` stays for agent/script clients; app users get per-user JWTs |

---

## iOS Implementation

### 1. Add KeychainSwift via SPM

In `Package.swift` (or Xcode Package Dependencies):
```
https://github.com/evgenyneu/keychain-swift  tag: 24.0.0
```

### 2. TokenStore

New file: `Sources/Data/Auth/TokenStore.swift`

```swift
import Foundation
import KeychainSwift

@MainActor
final class TokenStore {
    static let shared = TokenStore()
    private let keychain = KeychainSwift()

    private enum Key {
        static let accessToken  = "orca_access_token"
        static let refreshToken = "orca_refresh_token"
        static let appleUserID  = "apple_user_id"
    }

    var accessToken: String? { keychain.get(Key.accessToken) }
    var refreshToken: String? { keychain.get(Key.refreshToken) }
    var appleUserID: String? { keychain.get(Key.appleUserID) }
    var isAuthenticated: Bool { accessToken != nil }

    func store(accessToken: String, refreshToken: String) {
        keychain.set(accessToken,  forKey: Key.accessToken,  withAccess: .accessibleWhenUnlocked)
        keychain.set(refreshToken, forKey: Key.refreshToken, withAccess: .accessibleAfterFirstUnlock)
    }

    func storeAppleUserID(_ id: String) {
        keychain.set(id, forKey: Key.appleUserID, withAccess: .accessibleWhenUnlocked)
    }

    func clear() {
        keychain.delete(Key.accessToken)
        keychain.delete(Key.refreshToken)
        keychain.delete(Key.appleUserID)
    }
}
```

### 3. SignInWithAppleManager

New file: `Sources/Data/Auth/SignInWithAppleManager.swift`

```swift
import AuthenticationServices
import Foundation

@MainActor
final class SignInWithAppleManager: NSObject, ASAuthorizationControllerDelegate {
    static let shared = SignInWithAppleManager()

    var onSuccess: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    func signIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization auth: ASAuthorization) {
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            onFailure?(AuthError.missingCredential)
            return
        }

        TokenStore.shared.storeAppleUserID(credential.user)

        Task {
            do {
                let tokens = try await APIClient.shared.exchangeAppleToken(
                    identityToken: identityToken,
                    appleUserID: credential.user
                )
                TokenStore.shared.store(
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken
                )
                onSuccess?()
            } catch {
                onFailure?(error)
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        onFailure?(error)
    }
}

enum AuthError: Error {
    case missingCredential
    case sessionExpired
    case tokenRefreshFailed
}
```

### 4. Update AppState

Key changes to `Sources/App/AppState.swift`:

```swift
// Replace isAuthenticated init
@Published var isAuthenticated = TokenStore.shared.isAuthenticated

// Replace authenticate(token:) with:
func signInWithApple() {
    SignInWithAppleManager.shared.onSuccess = { [weak self] in
        Task { @MainActor in
            self?.isAuthenticated = true
            self?.currentUser = TeamMember(id: UUID(), name: "User", avatarColor: "#6B46C1")
        }
    }
    SignInWithAppleManager.shared.onFailure = { [weak self] error in
        Task { @MainActor in
            self?.isLoading = false
            self?.errorMessage = error.localizedDescription
            self?.showError = true
        }
    }
    SignInWithAppleManager.shared.signIn()
}

// Replace logout() token cleanup:
func logout() {
    TokenStore.shared.clear()
    isAuthenticated = false
    // ... rest unchanged
}
```

Remove `storeToken()`, `loadStoredToken()`, `clearToken()` — `TokenStore` owns this now.

### 5. Update PushNotificationService

Replace [Sources/Data/Remote/PushNotificationService.swift:14](../Sources/Data/Remote/PushNotificationService.swift):

```swift
// Remove:
private let authToken = "<64-hex-token-literal — REDACTED; this hardcoded pattern is exactly what SEC-007 removed>"

// Replace uses of authToken with:
private var authToken: String? { TokenStore.shared.accessToken }

// Guard at call sites:
guard let token = authToken else { return }
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

### 6. Silent Token Refresh

In `APIClient`, intercept 401 responses:

```swift
func authenticatedRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var req = request
    if let token = TokenStore.shared.accessToken {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: req)
    let http = response as! HTTPURLResponse

    if http.statusCode == 401 {
        try await refreshTokens()
        return try await authenticatedRequest(request) // one retry
    }

    return (data, http)
}

private func refreshTokens() async throws {
    guard let refresh = TokenStore.shared.refreshToken else {
        throw AuthError.sessionExpired
    }
    let tokens = try await refresh(refreshToken: refresh)
    await MainActor.run {
        TokenStore.shared.store(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
    }
}
```

---

## Backend Implementation

### New Endpoints

```
POST /auth/apple/callback    Exchange Apple identityToken → ORCA MC JWT pair
POST /auth/refresh           Rotate refresh token → new access + refresh tokens
POST /auth/logout            Revoke refresh token server-side
GET  /auth/me                Return current user profile
```

App users hit these endpoints. Agent/script clients continue using `LOCAL_AUTH_TOKEN` unchanged — no migration needed for non-app clients.

### Apple Token Verification (Python/FastAPI)

```python
import httpx, jwt

APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER   = "https://appleid.apple.com"
APPLE_AUDIENCE = "com.openclaw.pod"  # must match app Bundle ID

async def verify_apple_token(identity_token: str) -> dict:
    async with httpx.AsyncClient() as client:
        jwks = (await client.get(APPLE_JWKS_URL)).json()

    header = jwt.get_unverified_header(identity_token)
    key = next(k for k in jwks["keys"] if k["kid"] == header["kid"])
    public_key = jwt.algorithms.RSAAlgorithm.from_jwk(key)

    return jwt.decode(
        identity_token,
        public_key,
        algorithms=["RS256"],
        audience=APPLE_AUDIENCE,
        issuer=APPLE_ISSUER,
    )
    # Returns: {"sub": apple_user_id, "email": ..., "email_verified": True, ...}
```

### `/auth/apple/callback` endpoint

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/auth")

class AppleCallbackRequest(BaseModel):
    identity_token: str
    apple_user_id: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = 1800  # 30 min

@router.post("/apple/callback", response_model=TokenResponse)
async def apple_callback(body: AppleCallbackRequest, db: AsyncSession = Depends(get_db)):
    try:
        claims = await verify_apple_token(body.identity_token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid Apple identity token")

    if claims["sub"] != body.apple_user_id:
        raise HTTPException(status_code=401, detail="User ID mismatch")

    user = await get_or_create_user(db, apple_user_id=claims["sub"], email=claims.get("email"))
    return create_token_pair(user.id)
```

### Token issuance

```python
import secrets
from datetime import datetime, timedelta, timezone
import jwt

SECRET_KEY = os.environ["JWT_SECRET_KEY"]  # openssl rand -hex 32, stored in .env
ALGORITHM  = "HS256"
ACCESS_TTL  = timedelta(minutes=30)
REFRESH_TTL = timedelta(days=30)

# Stored in DB or Redis: refresh_token (opaque) → user_id
def create_token_pair(user_id: str) -> TokenResponse:
    now    = datetime.now(timezone.utc)
    access = jwt.encode(
        {"sub": user_id, "exp": now + ACCESS_TTL, "iat": now},
        SECRET_KEY, algorithm=ALGORITHM
    )
    refresh = secrets.token_urlsafe(48)
    store_refresh_token(refresh, user_id, expires=now + REFRESH_TTL)
    return TokenResponse(access_token=access, refresh_token=refresh)
```

---

## New Backend Env Vars Required

| Variable | Value | How to generate |
|----------|-------|-----------------|
| `JWT_SECRET_KEY` | New secret | `openssl rand -hex 32` |
| `APPLE_BUNDLE_ID` | `com.orcamc.pod` | Locked |

These go in the backend container env alongside `LOCAL_AUTH_TOKEN`. Tony sets these at rotation time (Step 4).

---

## Decisions — Locked by Tony (2026-05-03)

1. **Bundle ID:** `com.orcamc.pod` — confirmed in both `workspace-maui/pod.xcodeproj` and `~/pod-app/pod.xcodeproj`
2. **Refresh token storage:** Postgres — `user_refresh_tokens(id, user_id, token_hash, issued_at, expires_at, revoked_at, last_used_at, device_id)`. Hash the token, never store plaintext.
3. **User table:** Same `mission_control` Postgres DB — two tables: `users(id, apple_user_id, created_at, display_name, last_seen_at)` and `user_sessions(id, user_id, device_id, jwt_id, issued_at, expires_at, revoked_at)`. Access token TTL: ~1h.
4. **Email scope:** Skip — Apple `userID` (sub claim) is the stable identifier. No email needed for this app.
5. **Timing:** Ship SIWA first, rotate bearer at SIWA cutover — single rebuild, single rotation. Blast radius confirmed contained: all repos private, `.ipa` on Shaka's iPad only, token never left the team ecosystem. No interim Keychain step needed.

---

## Implementation Order (when Tony gives go-ahead)

1. Backend: add `users` table, `user_sessions` table (or Redis keys), `JWT_SECRET_KEY` to env
2. Backend: implement `/auth/apple/callback`, `/auth/refresh`, `/auth/logout`
3. iOS: add KeychainSwift SPM dep, add `TokenStore`, `SignInWithAppleManager`
4. iOS: update `AppState` — replace manual token flow with `signInWithApple()`
5. iOS: update `PushNotificationService` — read from `TokenStore`
6. iOS: add `AuthenticationServices` entitlement + SIWA capability in Xcode
7. Test: sign in on device, verify token stored in Keychain, verify push registration uses JWT
8. Tony: rotate `LOCAL_AUTH_TOKEN` (Step 4 from Phase 2.1 plan)

---

## Files Touched

| File | Change |
|------|--------|
| `Sources/Data/Auth/TokenStore.swift` | New |
| `Sources/Data/Auth/SignInWithAppleManager.swift` | New |
| `Sources/App/AppState.swift` | Replace token flow |
| `Sources/Data/Remote/PushNotificationService.swift` | Replace `authToken` literal |
| `Sources/Data/Remote/APIClient.swift` | Add refresh interceptor |
| `backend/app/api/auth.py` | New endpoint file |
| `backend/app/core/config.py` | Add `JWT_SECRET_KEY`, `APPLE_BUNDLE_ID` |
| `backend/app/models/user.py` | New user + session models |
| `Package.swift` | Add KeychainSwift dependency |
