# Tasks

## 1. Client state and persistence

- [x] 1.1 Add `refresh_token`, `expires_at` and `refresh` (kind, token_endpoint, client_id) fields to the client class in `lua/neoment/matrix/client.lua`; verify with a test that `client.new` leaves them nil and a session without them behaves as non-expiring
- [x] 1.2 Persist the three fields in `storage.save_session` and restore them in `restore_session`; skip the 7-day age check when a refresh token is present; extend `tests/storage_spec.lua` to cover round-trip, old-format file, and the age-limit scenarios

## 2. Token refresh core

- [x] 2.1 Expose HTTP `status` on errors from `api.handler` in `lua/neoment/matrix/api.lua`; verify with `tests/matrix_api_spec.lua` that a 401 body yields `status = 401` and `errcode`
- [x] 2.2 Create `lua/neoment/matrix/token.lua` with `refresh(cb)` for the legacy `/refresh` endpoint and the OAuth `grant_type=refresh_token` endpoint, applying and saving rotated values (keeping the old refresh token if none returned); verify with a new `tests/matrix_token_spec.lua` using mocked `curl` for both methods
- [x] 2.3 Add single-flight behavior and `ensure_fresh(cb)` (60 s skew, no-op without `expires_at`); verify in `tests/matrix_token_spec.lua` that three concurrent callers cause one refresh request and all see the new token
- [x] 2.4 Classify refresh failures: 4xx / `invalid_grant` / `M_UNKNOWN_TOKEN` as `session_expired`, network error and 5xx as transient (session untouched); verify both in `tests/matrix_token_spec.lua`

## 3. Authenticated request wrapper

- [x] 3.1 Add `api.authed.get/post/put/delete` that call `ensure_fresh`, inject `Authorization`, and on `401 M_UNKNOWN_TOKEN` + `soft_logout` refresh and retry once; verify in `tests/matrix_api_spec.lua`: proactive refresh, reactive retry succeeds, second 401 not retried, hard logout does not refresh
- [x] 3.2 Migrate every hand-built `Authorization` header in `lua/neoment/matrix/init.lua` (including `get_sync` users and `logout`) and `lua/neoment/matrix/event.lua:119` to the wrapper; verify with `grep -rn "Bearer" lua` returning only the wrapper and the full `devbox run test` passing

## 4. Login and session lifecycle

- [x] 4.1 Send `refresh_token = true` in the password login request and store `refresh_token` and `expires_at` from the response in `matrix.login`; verify with a login test covering responses with and without refresh fields
- [x] 4.2 Implement `on_session_expired` (stop sync, clear saved session, reset client, notify "please log in again") in `lua/neoment/init.lua`, trigger it from `session_expired` errors and hard-logout 401s, and make `lua/neoment/sync.lua` stop retrying on it; verify with a sync test that a `session_expired` error stops the loop without the "Retrying..." path
- [x] 4.3 Add the one-time re-read of the session file when a refresh is permanently rejected (rotation race with another instance); verify with a test where the file holds a newer refresh token

## 5. Media URLs

- [x] 5.1 Remove `?access_token=` from URLs stored by `lua/neoment/matrix/event.lua` and give `storage.fetch_to_temp` an optional `headers` argument used by download callers; add `storage.fetch_image_source(url, cb)` so `room.lua` and `room_info.lua` hand `snacks.image` a local file downloaded with the current token; verify with `tests/media_url_spec.lua` / `room_info_spec.lua` that stored URLs carry no token and downloads carry the current one
- [x] 5.2 Verify end to end that `grep -rn "access_token=" lua` only matches the helper, and add a test that a token change between event processing and display yields the new token in the URL

## 6. Integration and docs

- [x] 6.1 Add a sync-level test where `/sync` returns `401 soft_logout`, refresh succeeds, and `/sync` is retried with the same `since` and no error notification; verify it passes
- [x] 6.2 Document refresh-token behavior and the `client.refresh` contract for the upcoming OAuth login in the README, and run `devbox run test` to confirm the full suite passes
