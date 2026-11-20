## 1. Fix and verify logout

- [x] 1.1 Add a failing test in `tests/matrix_auth_spec.lua` using the real `matrix.logout` with mocked `curl`: after a successful `/logout`, `matrix.is_logged_in()` is `false`, `client.client.rooms` is empty, and `access_token`, `user_id` and `sync_token` are nil, while `homeserver` and `device_id` are kept
- [x] 1.2 Add a test that a rejected `/logout` leaves the access token and rooms in place
- [x] 1.3 In `lua/neoment/matrix/init.lua`, replace `client.new(c.homeserver)` in `M.logout`'s `finish` with `client.set_homeserver(c.homeserver)`; verify the new tests pass
- [x] 1.4 Add a test for the OAuth revocation path (`refresh.kind == "oauth"`) that a successful revoke also clears the client
- [x] 1.5 Run `devbox run test` and confirm the full suite passes
- [x] 1.6 In `lua/neoment/init.lua`, stop syncing only after the logout succeeds; test in `tests/login_flow_spec.lua` that a failed logout does not stop sync
- [x] 1.7 In `matrix.sync`, discard a response whose client was replaced while the request was in flight (error flagged `stale`), and make `sync.lua` drop it without touching the loop state; tests in `tests/matrix_auth_spec.lua` and `tests/sync_spec.lua` (a stale response must not stop a sync started after it)
