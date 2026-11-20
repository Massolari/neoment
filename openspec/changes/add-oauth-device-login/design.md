# Design

## Context

See proposal.md for motivation. Current state:

- `matrix/auth.lua` owns discovery and login requests. `get_login_flows` returns the supported methods (`password`, `sso`) from `GET /_matrix/client/v3/login` and errors when none remain. `init.lua` keeps a `LOGIN_HANDLERS` table, runs the only method or asks with `vim.ui.select`, and guards async callbacks with `login_generation`.
- `matrix/token.lua` already refreshes OAuth sessions: with `client.refresh = { kind = "oauth", token_endpoint, client_id }` it posts a form-encoded `grant_type=refresh_token` request. Nothing produces such a session yet.
- `storage.save_session` already persists `refresh_token`, `expires_at` and `refresh`.
- `api.post_raw` sends a raw body with caller-supplied headers, which `token.lua` uses for forms. `api.get/post` take `opts.raw` curl arguments, used for timeouts.
- The client's `device_id` is the fixed string `neovim-matrix-client`, kept across `set_homeserver`.
- `matrix.logout` calls `POST /_matrix/client/v3/logout` through `api.authed`, then `init.lua` clears the saved session.
- `storage.lua` keeps files under `stdpath("data")/neoment/`: `data.json` (session), `ui_state.json`.

## Goals / Non-Goals

**Goals:**
- A device-code login that fits the existing login flow, handlers and cancellation model, and produces a session the existing refresh code can keep alive.
- Network logic testable with mocked HTTP and a fake clock, without a live MAS.

**Non-Goals:**
- Authorization code + PKCE with a local callback, and `account_management_uri` links (follow-ups in the issue).
- Changing how refresh, session expiry or sync work.
- Per-session device IDs. The fixed device ID is kept (see Risks).

## Decisions

**1. A new `matrix/oauth.lua` for the protocol, `auth.lua` only for discovery.** `oauth.lua` holds metadata parsing, registration, device authorization, polling, whoami and revocation as functions taking callbacks, with no UI. `auth.lua` gains `get_oauth_metadata(homeserver, cb)`, because discovery already lives there. `init.lua` stays the only place with prompts. *Alternative:* extend `auth.lua` with all of it — rejected, it would mix a polling state machine into the file that parses login flows.

**2. `oauth_device` joins the method list, with availability from `auth_metadata`.** `get_login_flows` fetches `/v3/login` and `/v1/auth_metadata` and appends `oauth_device` when the metadata passes the check in the spec. The two requests run in parallel and join; a missing or invalid metadata response only drops `oauth_device`. The "no supported method" error is raised only when the list is empty after both. `METHOD_ORDER` becomes `oauth_device, password, sso` and the result also carries the parsed metadata so `init.lua` does not fetch it twice. *Alternative:* a separate probe only when no other method fits — rejected, `oauth_device` must win over password on MAS servers that offer both.

**3. Preference is picked in `init.lua`, with `login_method` as the override.** When `login_method` is set, only that method is considered: supported → run it, else error naming it and the available ones. When unset, `oauth_device` is run if present; otherwise the existing "one method runs, several ask" rule applies unchanged. `login_method` is a top-level string option, validated against the three values, nil by default. *Alternative:* always ask when several methods exist — rejected, matrix.org would ask on every login and the issue asks to prefer OAuth.

**4. Client registration is saved per issuer in its own file.** `storage.get_oauth_client_id(issuer)` / `set_oauth_client_id(issuer, id)` / `clear_oauth_client_id(issuer)` use `stdpath("data")/neoment/oauth_clients.json`, a table keyed by issuer. It is separate from `data.json` because `clear_session` removes that file on logout and the `client_id` must survive it, and it is written even when `save_session` is false (it is not a credential; skipping it would register a new client on every login). Registration sends `client_name = "Neoment"`, `client_uri = "https://github.com/Massolari/neoment"`, `grant_types = {device_code, refresh_token}`, `token_endpoint_auth_method = "none"`, `application_type = "native"` as JSON, as RFC 7591 defines. If the device authorization request answers `invalid_client` (the server dropped the registration), the saved id is cleared and the user is told to try again; retrying automatically is left out to avoid a loop. *Alternative:* store it in `data.json` — rejected, lost on logout.

**5. Device authorization and the token request are form-encoded through `api.post_raw`.** `token.lua` has a private `form_encode`; move it to `util.lua` as `util.form_encode` and use it from both modules, rather than copying it. Requests carry `--connect-timeout`/`--max-time` like discovery. Responses of RFC 8628 errors are JSON bodies with an `error` string, which `api.handler` already turns into an error result with `status`; the error code is `err.error`, so polling matches on it. This differs from Matrix errors only in that `error` holds the code, not a message, so `oauth.lua` maps codes to user-facing messages itself.

**6. Polling is a timer loop that owns its cancellation.** `oauth.poll(opts, on_done)` returns a handle with `cancel()`. It schedules the next request with `vim.defer_fn` after `interval` seconds, so a slow request never overlaps the next one, adds 5 seconds on `slow_down`, tracks a deadline from `expires_in`, and treats network errors and 5xx as "keep going until the deadline". `init.lua` keeps the handle next to `pending_sso_listener`, cancels it on a new login and checks `login_generation` before acting on a result, matching the existing pattern. The clock and timer are injected (`opts.now`, `opts.defer`) so tests run without waiting. *Alternative:* `vim.uv` interval timer — rejected, it could fire again while a request is in flight.

**7. Session setup follows `login_request`.** On success `oauth.lua` returns the tokens; `init.lua` (through a `matrix`/`auth` function with the same stale-client and `is_current` guard as `login_request`) writes `access_token`, `refresh_token`, `expires_at` from `expires_in`, and `refresh = { kind = "oauth", token_endpoint, client_id, revocation_endpoint }`. `RefreshMethod` in `client.lua` gains `revocation_endpoint?`; `token.lua` ignores it. The user ID then comes from `api.authed.get(whoami)`, which works because the token and expiry are already set. If `whoami` fails the new token is revoked on a best-effort basis and the client is reset with `set_homeserver`, so no half-logged-in session is left. A response without `refresh_token` leaves `refresh_token` and `expires_at` unset, which `token.lua` already treats as non-expiring and non-refreshable.

**8. Logout branches on the refresh method.** `matrix.logout` checks `client.refresh`: for `kind == "oauth"` with a `revocation_endpoint` it posts `token`, `token_type_hint=refresh_token` and `client_id` (RFC 7009) and succeeds on a 200; otherwise it keeps the `/logout` call. Revoking the refresh token ends the whole MAS session, access token included. The request does not use `api.authed` because revocation needs no bearer token and must not trigger a refresh. A failure is returned to `init.lua`, which already keeps the session and reports "Logout failed". *Alternative:* also call `/logout` — rejected, MAS supports it only as a compatibility call, and one revocation is enough.

**9. The verification prompt is a notification, plus an optional browser open.** `init.lua` shows the URL and code with `notify.info` (so it stays in `:messages`) and, outside SSH sessions, `vim.ui.select` offers "Open in browser" through `vim.ui.open`. Polling starts before the prompt is answered, so it never blocks the login. The existing `is_remote_session` is reused. `vim.ui.open` failure shows the error and keeps polling, since the URL is on screen.

## Risks / Trade-offs

- [Fixed `device_id` means a second login on the same account from another Neovim reuses the same MAS device and replaces its session] → Same limitation as today's password and SSO login; per-install device IDs are a separate change.
- [Registration payload is untested against a real MAS] → Metadata parsing, registration, polling and revocation are tested with mocked responses taken from RFC 8628/7591/7009 and the MAS docs; the apply phase includes a manual check against a MAS instance (matrix.org or a local one) before the change is considered done.
- [Auto-preferring OAuth removes the password prompt on MAS servers for existing users] → `login_method = "password"` restores it, and saved sessions are unaffected.
- [A `client_id` saved for an issuer can become invalid] → `invalid_client` clears it, so the next login registers again; the user sees the server's message.
- [Moving `form_encode` touches the refresh module] → It is a pure function covered by the existing token tests, which must keep passing unchanged.
- [`slow_down` and a long `interval` make approval feel slow] → The interval follows the server as RFC 8628 requires; the prompt tells the user the login completes on its own after approval.
