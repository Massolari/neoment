## Context

See proposal.md for motivation. `matrix.logout` ends in a shared `finish` callback (used by the OAuth revocation path and the `/logout` path) that calls `client.new(c.homeserver)`. `client.new` returns early when `M.client` exists, so the reset does nothing. `client.set_homeserver(homeserver)` already sets `M.client = nil`, creates a fresh client and restores the previous device ID; login already relies on it to avoid leaking an old session.

## Goals / Non-Goals

**Goals:**
- A successful logout always leaves `client.client` fresh, whichever logout path ran.

**Non-Goals:**
- Changing `client.new` semantics; other callers rely on its early return.
- Changing revocation or saved-session clearing.
- Guarding every async callback (`send_message`, `load_more_messages`, ...) against late responses; only `/sync`, which runs continuously, is guarded.

## Decisions

**1. Reuse `client.set_homeserver` in `finish`.** It gives exactly the required reset (fresh tables, kept homeserver and device ID) with no new API. *Alternative:* add `client.reset()` or a `force` argument to `client.new` as the issue suggests: rejected, it would duplicate `set_homeserver` or add a flag with a single caller.

**2. Reset only inside the success branch of `error.map`.** Failed logouts keep the session so the user can retry, matching today's behavior and `add-oauth-device-login`.

**3. Stop syncing only after a successful logout.** A failed logout keeps the session, so syncing must go on. *Alternative:* keep stopping first: rejected, a rejected logout would leave a logged-in client that no longer syncs.

**4. Discard stale `/sync` responses.** `/sync` is a 30 s long poll, so a request can outlive the logout. `matrix.sync` remembers the client that made the request and, if it was replaced, returns an error flagged `stale`; `sync.lua` returns early on it without touching `keep_syncing`, `status` or `error_count`, because a sync started after a quick re-login owns that state. Using `session_expired` instead would stop the new loop.

**5. Test against the real client module.** Existing logout tests stub `matrix.logout`, which is why this went unnoticed. The new tests call the real `matrix.logout` with a mocked `curl` and assert on `matrix.is_logged_in()` and room state.

## Risks / Trade-offs

- [A token refresh in flight during logout] → `token.lua` already treats `client.client ~= c` as a changed session and aborts, so replacing the client is safe.
- [A `/sync` request in flight during logout] → its response is discarded as stale (decision 4).
- [Other late callbacks recreating rooms in the new client] → accepted, same as for session expiry today.
- [Callers holding a reference to the old `client.client` table] → They already handle replacement (login and session expiry do the same).
