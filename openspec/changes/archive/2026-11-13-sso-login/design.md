# Design

## Context

See proposal.md (Why) for the problem and specs/authentication/spec.md for the required behavior.

Current state:

- `matrix.login(username, password, cb)` (`lua/neoment/matrix/init.lua`) has these problems:
  - It derives the homeserver as `"https://" .. username:match("@.*:(.*)")`.
  - It calls `client.new(homeserver)`, which is a no-op when a client already exists.
  - It posts `m.login.password`.
- `init.lua`'s local `login()` prompts with `vim.fn.input`/`vim.fn.inputsecret`. After success it saves the session, starts sync and opens the room list.
- `api.get`/`api.post` wrap `neoment.curl` (a plenary curl fork). That wrapper does not follow redirects; `curl -L` can only be passed through the `raw` option, which `api.get` doesn't expose.
- `mozilla.org/.well-known/matrix/client` returns 301 to `www.mozilla.org`, so discovery must follow redirects.
- Tests mock `neoment.curl` through `package.loaded` (see `tests/matrix_api_spec.lua`).

## Goals / Non-Goals

**Goals:**
- Keep discovery, choosing a login method, and each login method as separate units that can be tested on their own.
- Make adding OAuth device-code login (#46) mean adding one login method plus one more check when choosing a method.

**Non-Goals:**
- No changes to session saving or restoring, or to token lifetime handling (#45).
- No general-purpose HTTP server. The listener understands exactly one GET request line.

## Decisions

### 1. Module layout

```
lua/neoment/matrix/auth.lua    -- pure-ish protocol layer (no UI)
    discover(server_name, cb)          -> base_url (never errors; falls back)
    get_login_flows(homeserver, cb)    -> Error<{ "password"|"sso" ... }>
    login_password(user, password, cb) -> Error<nil>
    sso_redirect_url(homeserver, redirect_url) -> string
    login_token(token, cb)             -> Error<nil>
    parse_login_token(input)           -> string|nil   (URL or bare token)
    parse_server_name(input)           -> string|nil, user|nil

lua/neoment/sso_listener.lua   -- vim.uv loopback listener
    start(on_token) -> { port, close() } | Error

lua/neoment/init.lua           -- interactive orchestration (prompts, select, notify)
```

`matrix.login` keeps working as a thin wrapper around `auth.login_password` so existing callers don't break.

`auth.lua` sets the homeserver with a new `client.set_homeserver(url)` instead of `client.new`. This fixes the no-op when a client already exists, for example after logging out and logging in again in the same session.

*Alternative:* put everything in `matrix/init.lua`. That file is already over 1300 lines, and keeping the network layer separate from the UI makes testing easier.

### 2. Choosing a login method is a list of handlers

`init.lua` builds a table of supported methods in a fixed order, `{ password = fn, sso = fn }`. It keeps only the ones the server advertises:

- If one remains, it runs that one.
- If several remain, it asks with `vim.ui.select`.
- If none remain, it shows an error.

Adding `oauth_device` later means adding one entry to this table, plus one check in `get_login_flows` against `auth_metadata`.

### 3. Discovery follows redirects with `raw = { "-L" }`

Add an optional `raw` field to `neoment.matrix.api.RequestOptions` and pass it through in `api.get`. Discovery calls `api.get(url, cb, { raw = { "-L" } })`. Any error result, whether a request failure or JSON that won't decode (an HTML 404 page, for example), falls back to `https://<server_name>`. Discovery therefore never fails; it always produces a URL.

*Alternative:* resolve `Location` headers manually. That's more code with no benefit.

### 4. Loopback listener

```
 vim.uv.new_tcp():bind("127.0.0.1", 0) -> getsockname().port
        |
        +-- on connection: read until "\r\n\r\n" (cap 8 KiB)
        |     parse "GET <path>?<query> HTTP/1.x"
        |     loginToken present? -> 200 "Login complete, you can close this tab"
        |                            close listener, vim.schedule(on_token(token))
        |     otherwise          -> 400, keep listening (favicon, probes)
        +-- timer (120 s) -> close, on_timeout()
```

Details:

- `redirectUrl` is `http://127.0.0.1:<port>/`. Using the IP rather than `localhost` avoids IPv6 `::1` mismatches.
- All `vim.uv` callbacks run in a fast context, so user-facing callbacks are wrapped in `vim.schedule` (see the AGENTS.md async rule).
- `close()` is safe to call more than once, and it stops both the timer and the server. It is also called on timeout, on cancel, and after a token arrives.

*Alternative:* `python -m http.server` or `nc`. Both are external dependencies and handle query parsing poorly.

### 5. Manual fallback flow

```
 sso selected
   |
   +-- SSH_CONNECTION/SSH_TTY set? -- yes --> notify(SSO URL) -> paste prompt
   |
   no
   v
 start listener -> vim.ui.open(sso_url)  (on open failure: notify URL)
   |
   +-- token via callback ------------------> login_token
   +-- 120 s timeout -> close listener -----> paste prompt
```

The paste prompt uses `vim.ui.input`; its input goes through `parse_login_token`:

- If the input contains `loginToken=`, the query value is URL-decoded and used.
- Otherwise the trimmed input is used as the token.
- If the input is empty or the prompt is cancelled, the login is cancelled.

The listener and the paste prompt never run at the same time, so there's no race and no need to close a prompt from code. In remote mode the listener is still not started. The `redirectUrl` stays `http://127.0.0.1:<port>/` with a placeholder port: the page fails to load, which is expected, and the user copies the URL from the address bar.

### 6. Prompts

The first prompt changes from "Username:" to "Matrix ID or server:". The password prompt still uses `vim.fn.inputsecret`. The method choice and the paste prompt use `vim.ui.*`, so pickers such as snacks or telescope can show them.

## Risks / Trade-offs

- [Some servers send the redirect only after a consent page, or use the `localhost` vs `127.0.0.1` distinction] → The fallback covers it, and the timeout message tells the user to paste the URL.
- [A local process could send a fake callback with an attacker's token] → It would only log the user into the attacker's account, which is low impact. The listener binds to loopback only and closes after the first valid token.
- [SSH detection misses mosh or nested tmux sessions] → The timeout falls back to the paste prompt.
- [`vim.ui.open` fails because no opener is configured] → The client shows a notification with the SSO URL so the user can open it manually.
- [The login token is single-use and short-lived (about 2 min on MAS)] → Paste instructions ask the user to paste promptly. An `M_FORBIDDEN` error is shown as is, and the user can retry with `:Neoment`.
- [A session saved by an older version] → Sessions store `homeserver` directly, so restore does not need discovery and nothing changes.
