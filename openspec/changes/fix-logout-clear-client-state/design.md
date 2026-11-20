## Context

See proposal.md for motivation. `matrix.logout` ends in a shared `finish` callback (used by the OAuth revocation path and the `/logout` path) that calls `client.new(c.homeserver)`. `client.new` returns early when `M.client` exists, so the reset does nothing. `client.set_homeserver(homeserver)` already sets `M.client = nil`, creates a fresh client and restores the previous device ID; login already relies on it to avoid leaking an old session.

## Goals / Non-Goals

**Goals:**
- A successful logout always leaves `client.client` fresh, whichever logout path ran.

**Non-Goals:**
- Changing `client.new` semantics; other callers rely on its early return.
- Changing failure handling, revocation, or saved-session clearing.

## Decisions

**1. Reuse `client.set_homeserver` in `finish`.** It gives exactly the required reset (fresh tables, kept homeserver and device ID) with no new API. *Alternative:* add `client.reset()` or a `force` argument to `client.new` as the issue suggests: rejected, it would duplicate `set_homeserver` or add a flag with a single caller.

**2. Reset only inside the success branch of `error.map`.** Failed logouts keep the session so the user can retry, matching today's behavior and `add-oauth-device-login`.

**3. Test against the real client module.** Existing logout tests stub `matrix.logout`, which is why this went unnoticed. The new tests call the real `matrix.logout` with a mocked `curl` and assert on `matrix.is_logged_in()` and room state.

## Risks / Trade-offs

- [A token refresh in flight during logout] → `token.lua` already treats `client.client ~= c` as a changed session and aborts, so replacing the client is safe.
- [Callers holding a reference to the old `client.client` table] → They already handle replacement (login and session expiry do the same).
