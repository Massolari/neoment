# Proposal

## Why

Users of homeservers that require Single Sign-On cannot log in (issue #5). Mozilla's homeserver is one example. Two separate problems block them:

1. Neoment builds the homeserver URL as `https://<server_name>` and never reads `/.well-known/matrix/client`. For `@you:mozilla.org` it sends the login request to `https://mozilla.org`, which redirects with a 301, and login fails immediately. The real homeserver is `https://mozilla.modular.im`.
2. Neoment only knows `m.login.password`. Mozilla's server offers only `m.login.sso` and `m.login.token`.

## What Changes

- Find the homeserver for a user ID through `/.well-known/matrix/client`, following redirects. Fall back to `https://<server_name>` when discovery returns nothing usable.
- Have the first prompt accept a full Matrix ID (`@you:mozilla.org`) or just a server name (`mozilla.org`). SSO users often don't know their full Matrix ID.
- Ask the homeserver which login methods it supports (`GET /_matrix/client/v3/login`) before prompting for credentials. If it supports exactly one method Neoment can use, use it. If it supports both, let the user pick with `vim.ui.select`.
- Keep the current password prompt for servers that offer `m.login.password`.
- Add SSO login for servers that offer `m.login.sso`:
  1. Neoment listens on a temporary `127.0.0.1` port.
  2. It opens the homeserver's SSO page in the browser with `vim.ui.open`.
  3. When the browser is sent back to the local port, Neoment takes the `loginToken` from the URL.
  4. It exchanges the token through `POST /_matrix/client/v3/login` with `type = "m.login.token"`.
- Let the user paste the URL they landed on, for when the browser can't reach Neovim's local port (SSH, headless machines, blocked ports). Neoment asks for the URL right away when it detects an SSH session. Otherwise it asks only if no callback arrives within a timeout.
- Organize login methods so the list is easy to extend. OAuth 2.0 device-code login (#46) can then be added as another method later.

## Out of scope

- OAuth 2.0 login, including device-code login (#46).
- Refresh tokens and expiring access tokens (#45). The SSO path does not request a refresh token, so the token it receives does not expire, like today's password token.
- Changes to how sessions are saved and restored.

## Capabilities

### New Capabilities
- `authentication`: How the client finds the user's homeserver, chooses a login method, and logs in with a password or SSO.

### Modified Capabilities
<!-- none -->

## Impact

- `lua/neoment/matrix/init.lua`:
  - `M.login` is split into discovery, querying login methods, and one login function per method (password, SSO token).
  - The `https://` + server name logic is replaced by discovery.
- `lua/neoment/init.lua`: the interactive `login()` flow chooses its prompts based on the login method the server supports.
- New module for the local SSO callback listener (uses `vim.uv`). It has no new external dependencies.
- `lua/neoment/matrix/api.lua`: GET requests need a way to follow redirects, which discovery requires.
- `README.md`: the first-time setup section mentions SSO.
- New tests: discovery, choosing the login method, parsing the redirect URL, and the listener.
