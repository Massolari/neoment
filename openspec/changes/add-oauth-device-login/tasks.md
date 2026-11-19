# Tasks

## 1. Discovery and method selection

- [ ] 1.1 Add `auth.get_oauth_metadata(homeserver, cb)` in `lua/neoment/matrix/auth.lua` that requests `/_matrix/client/v1/auth_metadata`, checks the device code grant and the four required endpoints, and returns nothing (no error) when unsupported; verify with `tests/matrix_auth_spec.lua` cases for supported, grant missing, 404 `M_UNRECOGNIZED`, non-JSON body and missing `registration_endpoint`
- [ ] 1.2 Make `auth.get_login_flows` add `oauth_device` (ordered first) from the metadata, run both requests in parallel, return the metadata with the methods, and only error when no method remains; verify in `tests/matrix_auth_spec.lua` that OAuth-only servers succeed, a metadata failure drops only `oauth_device`, and the existing password/SSO cases still pass
- [ ] 1.3 Add the `login_method` option (`"password"|"sso"|"oauth_device"`, nil by default) to `lua/neoment/config.lua` with a validation error for other values, and apply the selection rules in `lua/neoment/init.lua` (forced method, OAuth preferred, else current behavior, error naming the method and the offered ones); verify in `tests/login_flow_spec.lua` for each scenario of the modified "Login method selection" requirement
- [ ] 1.4 Document `login_method` in the `README.md` config example and options text, and verify the example block matches the defaults in `config.lua`

## 2. OAuth protocol module

- [ ] 2.1 Move `form_encode` from `lua/neoment/matrix/token.lua` to `util.form_encode` and use it from `token.lua`; verify `tests/matrix_token_spec.lua` passes unchanged
- [ ] 2.2 Add per-issuer client ID storage (`get/set/clear_oauth_client_id`, file `oauth_clients.json` under `stdpath("data")/neoment`, written regardless of `save_session`) to `lua/neoment/storage.lua`; verify in `tests/storage_spec.lua` the round trip, two issuers, clearing one, a missing/corrupt file, and that `clear_session` leaves it in place
- [ ] 2.3 Create `lua/neoment/matrix/oauth.lua` with `register_client` (JSON registration request, reuse of the saved `client_id`, error on a missing id); verify in a new `tests/oauth_spec.lua` with mocked HTTP: first login registers and saves, second login sends no request, a different issuer registers again, failure and missing `client_id` give errors
- [ ] 2.4 Add `request_device_code` (form-encoded, scope `urn:matrix:client:api:* urn:matrix:client:device:<device_id>`, `invalid_client` clears the saved id) and the verification URL choice (`verification_uri_complete` or `verification_uri` + `user_code`); verify in `tests/oauth_spec.lua` the request body and scope, both URL shapes, and the `invalid_client` cleanup
- [ ] 2.5 Add `poll` with a cancel handle, injectable clock and timer, `interval` default 5 s, `slow_down` +5 s, deadline from `expires_in`, and the four error outcomes plus retry on network/5xx errors; verify in `tests/oauth_spec.lua` with a fake clock: pending keeps the interval, slow_down grows it, `expired_token`/deadline/`access_denied` stop with distinct errors, transient failure keeps polling, cancel stops further requests, and requests never overlap
- [ ] 2.6 Add `revoke` (form-encoded `token`, `token_type_hint`, `client_id` to the revocation endpoint); verify in `tests/oauth_spec.lua` the request body and that a non-2xx answer is an error

## 3. Login and session setup

- [ ] 3.1 Add the optional `revocation_endpoint` field to the client's `RefreshMethod` type in `lua/neoment/matrix/client.lua` (`revocation_endpoint?`), and the function that stores the token response on the client (access token, refresh token, `expires_at` from `expires_in`, `refresh = { kind = "oauth", token_endpoint, client_id, revocation_endpoint }`) with the same stale-client and superseded-attempt guards as `login_request`; verify in `tests/matrix_auth_spec.lua` stored fields, a response without `refresh_token`, a response without `access_token`, and a replaced client dropping the tokens
- [ ] 3.2 Read the user ID with `GET /_matrix/client/v3/account/whoami` after the token is stored, and on failure revoke the new token best-effort and reset the client; verify in `tests/oauth_spec.lua` or `tests/matrix_auth_spec.lua` that success sets `user_id`, and failure leaves no access token on the client and calls revoke
- [ ] 3.3 Add the `oauth_device` handler to `lua/neoment/init.lua`: register, request the device code, show URL and code through `notify`, offer `vim.ui.open` outside SSH sessions, poll, then run the existing login-result path; keep the polling handle with `pending_sso_listener` and cancel it, and ignore results, when a new login starts; verify in `tests/login_flow_spec.lua`: local session offers to open and polling continues if declined, SSH session never opens a browser, denial/expiry show an error and do not log in, a second `:Neoment` cancels the first poll, and success starts syncing and opens the room list
- [ ] 3.4 Verify the saved session round trip: after an `oauth_device` login the file written by `storage.save_session` holds the OAuth `refresh` table, and a restored session refreshes through `token.refresh` against the token endpoint; add the case to `tests/storage_spec.lua` or `tests/matrix_token_spec.lua`

## 4. Logout

- [ ] 4.1 Make `matrix.logout` in `lua/neoment/matrix/init.lua` revoke the refresh token through `oauth.revoke` for OAuth sessions with a revocation endpoint (no bearer header, no refresh), and keep `/logout` for every other session; verify with tests for: OAuth logout sends only the revocation request, a failed revocation returns an error and keeps the session in `init.lua`'s logout path, and a session without a revocation endpoint or a legacy session still calls `/logout`

## 5. Docs and integration

- [ ] 5.1 Update the "First Time Setup" section of `README.md` with the OAuth device flow (URL and code, works over SSH, automatic preference, `login_method`) and the saved `client_id` file; verify the steps against a manual run of `:Neoment`
- [ ] 5.2 Run `devbox run test` and `openspec validate add-oauth-device-login --strict`; verify both pass
- [ ] 5.3 Manually log in against a real MAS homeserver (for example `matrix.org`), check registration, approval in a browser, syncing, a token refresh after the access token expires, and `:NeomentLogout` revoking the session; record anything that differs from the mocked responses and fix it
