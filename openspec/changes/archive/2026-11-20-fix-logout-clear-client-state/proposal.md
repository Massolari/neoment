## Why

After a successful `:Neoment logout`, the client still holds the old access token, user ID, sync token and room data in memory, so `matrix.is_logged_in()` keeps returning `true`. Running `:Neoment` again opens the room list with a token the server already revoked instead of showing the login prompt. See GitHub issue #47.

## What Changes

- After a successful logout (regular `/logout` and OAuth revocation alike), discard the whole in-memory client session so no token, user, sync token, room, display name or presence data survives.
- Keep the homeserver URL and device ID so the next login targets the same server and device.
- Keep syncing when the logout fails, and discard `/sync` responses that outlive the session.
- Add regression tests: after a successful logout `is_logged_in()` is `false` and rooms are empty; after a failed logout the session is untouched.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities
- `authentication`: adds a requirement that a successful logout leaves the client logged out, with no session data left in memory.

## Impact

- `lua/neoment/matrix/init.lua`: `M.logout` resets the client through `client.set_homeserver` instead of the no-op `client.new`.
- `tests/`: new logout tests against the real client module.
- `lua/neoment/init.lua`: `M.logout` stops syncing only after the logout succeeds. The saved-session handling is unchanged.
- `lua/neoment/matrix/init.lua` (`matrix.sync`) and `lua/neoment/sync.lua`: a `/sync` response that arrives after the client was replaced is discarded without affecting the sync loop.
- Out of scope: logout failure behavior and OAuth revocation (owned by `add-oauth-device-login`), and making `client.new` replace an existing client.
