## Why

Matrix homeservers are moving to OAuth 2.0 (Matrix Authentication Service); `matrix.org` and `mozilla.org` already issue short-lived access tokens with a refresh token. Neoment assumes an access token never expires, so it cannot work against these homeservers and blocks any future OAuth login. See GitHub issue #45.

## What Changes

- Capture `refresh_token` and `expires_in_ms` from the login response, and request a refresh token at password login.
- Persist the refresh token, the expiry time and the refresh method in the saved session, and restore them on startup.
- Refresh the access token proactively shortly before it expires, and reactively on `401 M_UNKNOWN_TOKEN` with `soft_logout`, then retry the original request once.
- Support both refresh methods: legacy `POST /_matrix/client/v3/refresh`, and the OAuth 2.0 token endpoint with `grant_type=refresh_token`.
- Serialize refreshes so concurrent requests trigger a single refresh and the rest wait for it.
- Make the `/sync` long-poll recover when the token rotates or expires mid-request.
- Stop embedding `?access_token=` in stored media URLs; attach the current token when media is fetched or displayed.
- When refresh fails permanently, clear the session and tell the user to log in again.
- A saved session that holds a refresh token no longer expires after the fixed 7-day age limit.

## Capabilities

### New Capabilities
- `session-token-refresh`: Lifecycle of expiring access tokens: capture, persistence, proactive and reactive refresh, concurrency, sync recovery, media authentication, and failure handling.

### Modified Capabilities

(none)

## Impact

- `lua/neoment/matrix/client.lua`: client fields for refresh token, expiry, refresh method.
- `lua/neoment/matrix/api.lua`: central authenticated-request path with 401 handling and retry (replaces ~20 hand-built `Authorization` headers in `matrix/init.lua`, plus `matrix/event.lua`).
- `lua/neoment/matrix/init.lua`: login, new refresh logic, sync loop.
- `lua/neoment/storage.lua`: session save/restore, `fetch_to_temp` headers.
- `lua/neoment/matrix/event.lua`, `lua/neoment/room.lua`, `lua/neoment/room_info.lua`: media URL construction.
- `lua/neoment/sync.lua`, `lua/neoment/init.lua`: re-login handling.
- Session file format gains fields; old files remain readable (no migration needed).
- Out of scope: the OAuth login flow itself (device-code login issue). This change only consumes OAuth session metadata that flow will store.
