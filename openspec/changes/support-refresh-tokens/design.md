# Design

## Context

See proposal.md for motivation. Current state:

- `api.get/post/put/delete` are thin curl wrappers; every caller in `matrix/init.lua` (~20 sites), `matrix/event.lua` and `matrix/init.lua:logout` builds its own `Authorization = "Bearer " .. client.client.access_token` header, evaluated at call time.
- `api.handler` decodes the body and discards the HTTP status, so a `401` is indistinguishable from other errors except by `errcode`.
- Media URLs are built with `?access_token=` baked in at event-processing time (`matrix/event.lua`) and at display time (`room.lua`, `room_info.lua`). Message attachments keep the URL, so they go stale after rotation. Images are shown by `snacks.image`, which fetches the URL itself and cannot attach headers; downloads go through `storage.fetch_to_temp` (curl).
- `sync.lua` loops by calling `matrix.sync`; errors retry 3 times then stop.
- `storage.save_session` persists `access_token` only; `restore_session` rejects sessions older than 7 days.
- The OAuth login flow does not exist yet (separate issue), so no code path currently produces an OAuth session.

## Goals / Non-Goals

**Goals:**
- One place that owns token freshness, so call sites stop touching the token.
- Correct behavior with both refresh endpoints, testable without a live homeserver.

**Non-Goals:**
- OAuth login, client registration, and token revocation on logout via OAuth.
- Switching media to authenticated headers everywhere (snacks.image limits this).

## Decisions

**1. Authenticated request wrapper in `matrix/api.lua`.** Add `api.authed.get/post/put/delete` (same signatures as the current functions, minus the `Authorization` header). They (a) ensure the token is fresh via `ensure_fresh(cb)`, (b) inject the header from the current token, (c) on `401 M_UNKNOWN_TOKEN` + `soft_logout` call `refresh` and retry once. Migrate all `Authorization = ...` call sites to it. *Alternative:* patch each call site to call `ensure_fresh` first — rejected, ~20 duplicated edits and the reactive retry would still be missing. *Alternative:* a curl middleware — rejected, `curl.lua` is a vendored plenary wrapper.

**2. Expose HTTP status to the handler.** `handler` gains the response `status` and attaches it to errors as `status` so the wrapper can distinguish `401` and permanent (4xx) vs transient (5xx / curl failure) refresh failures. `get_sync` (used for blocking profile lookups) is migrated too, with the refresh skipped there only if unavoidable; otherwise it uses the current token.

**3. Refresh state machine in a new `matrix/token.lua`.** Holds `refresh(cb)` and `ensure_fresh(cb)`. A module-level `pending` list of callbacks gives single-flight: the first caller starts the HTTP request, later callers append to the list; all are invoked with the result. Expiry is stored as an absolute `expires_at` (os.time seconds); a request is "stale" when `expires_at - now < 60`. Absent `expires_at` means never proactively refresh. `api.lua` requires `token.lua` lazily to avoid a require cycle.

**4. Refresh method stored on the client.** `client.refresh = { kind = "legacy" | "oauth", token_endpoint?, client_id? }`, default legacy. Legacy: `POST {homeserver}/_matrix/client/v3/refresh` JSON `{refresh_token}`; response `access_token`, `refresh_token?`, `expires_in_ms?`. OAuth: form-encoded POST to `token_endpoint` with `grant_type`, `refresh_token`, `client_id`; response `access_token`, `refresh_token`, `expires_in` (seconds). The future OAuth login must populate `client.refresh`; this change defines and tests that contract with mocked responses only. Refresh tokens rotate on every OAuth refresh, so new values are persisted via `storage.save_session()` immediately after each successful refresh. If the response omits `refresh_token` (legacy allows this) the old one is kept.

**5. Login requests `refresh_token = true`** in the password login body, and `matrix.login` stores `refresh_token` and `expires_at`. Servers that don't support it ignore the field.

**6. Sync recovery needs no loop change beyond routing through the wrapper.** `matrix.sync` uses `api.authed.get`; a mid-poll `401` is refreshed and retried inside the wrapper with the same query (`since` is read from `client.sync_token` which has not advanced). Refresh failure surfaces as a distinguished error `session_expired`; `sync.lua` stops the loop (no retry-3-times) and `init.lua` runs the re-login path.

**7. Session ended path.** One function `M.on_session_expired` in `init.lua`: `sync.stop()`, `storage.clear_session()`, `matrix.client` reset, `notify.error("Session expired, please log in again")`. Triggered by permanent refresh failure and by hard-logout 401. Transient refresh failures return the error to the caller and leave state untouched.

**8. Media: build URLs at use time.** Stored URLs (`message.attachment.url`, thumbnails, avatars) become plain `.../media/download/...` without a token. `storage.fetch_to_temp` gains an optional `headers` argument and callers pass `Authorization: Bearer` (`util.media_headers`). Images shown by `snacks.image` are downloaded the same way by `storage.fetch_image_source`, which names the file after a hash of the token-free URL and hands snacks the local path, deduplicating downloads in flight. *Rejected:* appending `?access_token=<current>` to the URL given to snacks — snacks caches by source, so every refresh (every few minutes on Synapse) would re-download and re-convert every visible image and grow its cache without bound.

**9. 7-day session age check** applies only when the session has no refresh token; refreshable sessions are bounded by the server-side refresh-token lifetime.

## Risks / Trade-offs

- [Refresh token rotation race across two Neovim instances sharing one session file: the second instance's refresh token is invalidated] → On permanent failure, re-read the session file once and retry if its refresh token differs; otherwise end the session.
- [Migrating ~20 call sites risks regressions] → Mechanical change, covered by wrapper unit tests plus the existing suite; no behavior change when no refresh token is set.
- [Snacks image URL embeds a token that may expire while the image is loading] → Token is fresh (ensure_fresh called by the caller of the helper's wrapper path); a rare failure shows the existing image-load error and succeeds on reopen.
- [OAuth path untested against a real MAS] → Contract tested with mocked endpoint; real verification belongs to the OAuth login change.
- [Token appears in stored message tables today and in saved cache] → Removing it from stored data is an improvement.

## Migration Plan

No data migration: new session fields are optional, old files load as non-expiring sessions. Rollback is reverting the change; extra fields in the session file are ignored by old versions.
