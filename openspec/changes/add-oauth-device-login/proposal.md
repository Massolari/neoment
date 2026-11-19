# Proposal

## Why

Matrix is moving to OAuth 2.0 login through the Matrix Authentication Service (MAS). `matrix.org` and `mozilla.org` already run it, and offer the old password and SSO logins only through a compatibility layer. The OAuth 2.0 device authorization grant (RFC 8628) suits a terminal client: Neoment shows a URL and a code, the user approves in any browser on any machine, and Neoment polls for the token. It works over SSH and on headless machines and needs no local HTTP server. Refresh of OAuth tokens already exists (GitHub issue #45), so the login can now be added. See GitHub issue #46.

## What Changes

- Discover the OAuth server from `GET /_matrix/client/v1/auth_metadata` and offer a new `oauth_device` login method when the server supports the device authorization grant.
- Register Neoment as a public native client with dynamic client registration, save the `client_id` per issuer, and reuse it on later logins.
- Request a device code scoped to the Matrix client API and this device, show the verification URL and user code, and offer to open the URL with `vim.ui.open`.
- Poll the token endpoint at the server's interval, handling `authorization_pending`, `slow_down`, `expired_token` and `access_denied`.
- Resolve the user ID with `GET /_matrix/client/v3/account/whoami`, since the token response has none, and store the OAuth refresh method (`client.refresh`) so existing token refresh keeps the session alive.
- Prefer `oauth_device` automatically when the server offers it, falling back to password and SSO otherwise, and add a `login_method` config option to force a method.
- On `:NeomentLogout` of an OAuth session, revoke the token through the server's `revocation_endpoint`.

## Capabilities

### New Capabilities
- `oauth-device-login`: Logging in with the OAuth 2.0 device authorization grant: server discovery, client registration and reuse, device authorization, polling, session setup, and token revocation on logout.

### Modified Capabilities
- `authentication`: Login method selection gains the `oauth_device` method, its preference over password and SSO, and the option to force a method.

## Impact

- `lua/neoment/matrix/auth.lua`: `auth_metadata` discovery, `oauth_device` in the supported methods.
- New `lua/neoment/matrix/oauth.lua`: client registration, device authorization, polling, whoami, revocation.
- `lua/neoment/init.lua`: `oauth_device` login handler, method preference and `login_method`, logout of OAuth sessions.
- `lua/neoment/matrix/init.lua`: logout revokes OAuth tokens instead of calling `/logout`.
- `lua/neoment/matrix/client.lua`: `RefreshMethod` gains the revocation endpoint.
- `lua/neoment/storage.lua`: per-issuer `client_id` file that survives logout.
- `lua/neoment/config.lua`, `README.md`: `login_method` option and the new login flow documented.
- No change to saved sessions: they already hold `refresh`. Out of scope: OAuth authorization code + PKCE login and links to `account_management_uri`.
