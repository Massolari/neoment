# Tasks

## 1. HTTP and client groundwork

- [ ] 1.1 Add an optional `raw` field to `neoment.matrix.api.RequestOptions` and pass it through to `curl.get` in `api.get`. Verify with a new case in `tests/matrix_api_spec.lua` asserting `opts.raw` reaches the mocked `curl.get`.
- [ ] 1.2 Add `client.set_homeserver(url)` to `lua/neoment/matrix/client.lua`. It creates the client when there is none and otherwise replaces `homeserver`. Verify with a test that a second login on an existing client points at the new homeserver.

## 2. Auth protocol layer (`lua/neoment/matrix/auth.lua`)

- [ ] 2.1 Implement `parse_server_name(input)`. It returns the server name and the user for `@alice:example.org`, the server name only for `example.org`, and nil for empty input. Verify with unit tests in a new `tests/matrix_auth_spec.lua`.
- [ ] 2.2 Implement `discover(server_name, cb)`. It calls `api.get` with `raw = { "-L" }` on `/.well-known/matrix/client`, strips the trailing `/` from `base_url`, and falls back to `https://<server_name>` on any error or missing field. Verify with tests for delegation, a 404 or HTML body, a missing `m.homeserver`, and a request failure.
- [ ] 2.3 Implement `get_login_flows(homeserver, cb)`. It returns the list of supported methods (`password`, `sso`) found in `flows`, and returns an error that includes the homeserver URL if the request fails. Verify with tests for matrix.org-style (both), Mozilla-style (SSO + token only) and unsupported-only flows.
- [ ] 2.4 Move the password login into `auth.login_password(user, password, cb)` and keep `matrix.login` as a wrapper around it. Verify that the existing behavior (the request body sent and the `access_token`/`user_id` stored) is covered by a test.
- [ ] 2.5 Implement `sso_redirect_url(homeserver, redirect_url)`, which URL-encodes `redirectUrl`, and `login_token(token, cb)`, which posts `type = "m.login.token"`, `token` and `device_id` and stores `access_token`/`user_id`. Verify with tests for the exact URL, the request body, and the propagation of `M_FORBIDDEN` errors.
- [ ] 2.6 Implement `parse_login_token(input)`. A URL with `loginToken=` returns the URL-decoded value, a bare token returns the trimmed input, and empty input returns nil. Verify with unit tests, including a percent-encoded token.

## 3. Loopback listener (`lua/neoment/sso_listener.lua`)

- [ ] 3.1 Implement `start({ on_token, on_timeout, timeout_ms })`. It binds `127.0.0.1:0`, reports the port, reads the request line (8 KiB cap), answers 200 with a "you can close this tab" page when `loginToken` is present, answers 400 otherwise and keeps listening, and calls the callbacks through `vim.schedule`. Verify with a Busted test that connects with `vim.uv` TCP, sends `GET /?loginToken=abc HTTP/1.1`, and asserts `on_token("abc")` and a 200 response.
- [ ] 3.2 Add the timeout timer and a `close()` that is safe to call more than once and stops both the timer and the server. Verify with tests that a request without a token gets 400 without calling `on_token`, that a short timeout calls `on_timeout`, and that calling `close()` twice raises no error.

## 4. Interactive login flow (`lua/neoment/init.lua`)

- [ ] 4.1 Replace the username/password prompt with the new flow:
  1. Prompt "Matrix ID or server:".
  2. Discover the homeserver and call `client.set_homeserver`.
  3. Fetch the login flows.
  4. Run the matching handler from the method table: run it directly when one method is available, ask with `vim.ui.select` when several are, and show an error when none are.

  Factor the post-login steps (save the session, start sync, open the room list) into one function shared by all methods. Verify manually that `:Neoment` with a matrix.org account offers the choice and that password login still works.
- [ ] 4.2 Implement the password handler. It prompts for a username only when the input was a bare server name, then calls `inputsecret` and `auth.login_password`. Verify manually with a full Matrix ID and with a bare server name.
- [ ] 4.3 Implement the SSO handler:
  - If `SSH_CONNECTION`/`SSH_TTY` is set, show the SSO URL in a notification and go straight to the paste prompt.
  - Otherwise, start the listener, call `vim.ui.open(sso_url)` (and show the URL in a notification if that fails), and on timeout go to the paste prompt.
  - Exchange the token with `auth.login_token`.

  Verify manually that logging in with an `@…:mozilla.org` account completes through the browser, and that logging in with `SSH_TTY=x nvim` completes by pasting the URL.
- [ ] 4.4 Make cancelling cleanly stop the login at any prompt (empty Matrix ID, closed select, empty paste) without leaving a listener open. Verify manually by cancelling at each step and then checking that `:Neoment` can be run again.

## 5. Documentation and integration

- [ ] 5.1 Update `README.md`:
  - In "First Time Setup", describe the Matrix ID or server prompt, SSO through the browser, and the paste fallback over SSH.
  - Note in the `:Neoment` command description that SSO is supported.

  Verify that the README describes the new prompts exactly as they appear.
- [ ] 5.2 Run `devbox run test` and verify the whole suite passes.

## Workflow follow-up

- Close #5 when merged. OAuth device-code login (#46) and refresh tokens (#45) stay open.
- Archive the change after review.
