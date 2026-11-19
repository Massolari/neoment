# Spec Delta

## Purpose

Defines how the client finds the user's homeserver, chooses a login method the server supports, and logs the user in with a password or Single Sign-On.

## ADDED Requirements

### Requirement: Login accepts a Matrix ID or a server name
The client SHALL start an interactive login by asking for a Matrix user ID or a bare server name. It SHALL use the server-name part of the input to find the homeserver.

#### Scenario: User enters a full Matrix ID
- **WHEN** the user enters `@alice:example.org`
- **THEN** the client uses `example.org` as the server name

#### Scenario: User enters a bare server name
- **WHEN** the user enters `mozilla.org`
- **THEN** the client uses `mozilla.org` as the server name

#### Scenario: Input is empty
- **WHEN** the user submits an empty value
- **THEN** the login is cancelled without any network request

### Requirement: Homeserver discovery through well-known
The client SHALL find the homeserver base URL by requesting `https://<server_name>/.well-known/matrix/client` and following HTTP redirects. It SHALL use `m.homeserver.base_url`, with any trailing slash removed.

#### Scenario: Server delegates to another host
- **GIVEN** `https://mozilla.org/.well-known/matrix/client` redirects and finally returns `{"m.homeserver": {"base_url": "https://mozilla.modular.im/"}}`
- **WHEN** the user logs in as `@alice:mozilla.org`
- **THEN** all login requests are sent to `https://mozilla.modular.im`

#### Scenario: Well-known is missing or invalid
- **WHEN** the well-known request fails, returns a non-JSON body, or has no `m.homeserver.base_url`
- **THEN** the client uses `https://<server_name>` as the homeserver

### Requirement: Login method selection
The client SHALL request `GET /_matrix/client/v3/login` and offer only login methods it supports and the server advertises. Supported methods are password (`m.login.password`) and SSO (`m.login.sso`).

#### Scenario: Only password is offered
- **WHEN** the server advertises `m.login.password` and not `m.login.sso`
- **THEN** the client uses password login without asking which method to use

#### Scenario: Only SSO is offered
- **WHEN** the server advertises `m.login.sso` and `m.login.token` but not `m.login.password`
- **THEN** the client uses SSO login without asking which method to use

#### Scenario: Both password and SSO are offered
- **WHEN** the server advertises both `m.login.password` and `m.login.sso`
- **THEN** the client asks the user to choose between password and SSO

#### Scenario: No supported method is offered
- **WHEN** the server advertises neither `m.login.password` nor `m.login.sso`
- **THEN** the client shows an error naming the advertised flow types and does not log in

#### Scenario: Login flows cannot be fetched
- **WHEN** the `GET /_matrix/client/v3/login` request fails
- **THEN** the client shows an error that includes the homeserver URL and does not log in

### Requirement: Password login
The client SHALL log in with `m.login.password`, using the user's Matrix ID and a password typed without being shown on screen.

#### Scenario: Password login with a full Matrix ID
- **GIVEN** the user entered `@alice:example.org` and password login was selected
- **WHEN** the user enters their password
- **THEN** the client sends `m.login.password` with user `@alice:example.org` to the discovered homeserver

#### Scenario: Password login with a bare server name
- **GIVEN** the user entered `example.org` and password login was selected
- **WHEN** the client prompts for a username and the user enters `alice`
- **THEN** the client asks for the password and sends `m.login.password` with user `alice`

### Requirement: SSO login through a local callback
The client SHALL complete SSO by listening on `127.0.0.1` on a free port, opening `<homeserver>/_matrix/client/v3/login/sso/redirect` in the user's browser with a `redirectUrl` that points to that address, and exchanging the returned `loginToken` with `m.login.token`.

#### Scenario: Browser returns to the local callback
- **GIVEN** SSO login was selected and the session is not remote
- **WHEN** the user finishes SSO in the browser and the browser requests the callback URL with `loginToken=XYZ`
- **THEN** the client sends `POST /_matrix/client/v3/login` with `type = "m.login.token"`, `token = "XYZ"` and the client's device ID
- **AND** the browser receives a page saying it can be closed
- **AND** the listener is closed

#### Scenario: Callback request without a login token
- **WHEN** the listener receives a request that has no `loginToken` query parameter
- **THEN** the request gets an error response and the client keeps waiting for a valid callback

#### Scenario: Listener only accepts local connections
- **WHEN** SSO login is in progress
- **THEN** the callback listener is bound only to the loopback address `127.0.0.1`

### Requirement: Manual SSO fallback
The client SHALL let the user paste the URL their browser was redirected to, or the bare login token, when the local callback cannot be used. It SHALL ask for this right away in a remote (SSH) session, and after a timeout otherwise.

#### Scenario: Remote session
- **GIVEN** SSO login was selected and the `SSH_CONNECTION` or `SSH_TTY` environment variable is set
- **WHEN** SSO login starts
- **THEN** the client shows the SSO URL for the user to open and asks them to paste the redirected URL or token

#### Scenario: Local callback times out
- **GIVEN** SSO login was selected in a local session
- **WHEN** no valid callback arrives before the timeout
- **THEN** the client closes the listener and asks the user to paste the redirected URL or token

#### Scenario: User pastes the redirected URL
- **WHEN** the user pastes `http://127.0.0.1:PORT/?loginToken=XYZ`
- **THEN** the client extracts `XYZ` and exchanges it with `m.login.token`

#### Scenario: User pastes a bare token
- **WHEN** the user pastes `XYZ`, which is not a URL
- **THEN** the client exchanges `XYZ` with `m.login.token`

#### Scenario: User cancels the paste prompt
- **WHEN** the user submits an empty value or cancels
- **THEN** the login is cancelled and no listener stays open

### Requirement: Login result
After a successful login with any method, the client SHALL store the access token, user ID and homeserver from the response, then continue as it does after password login today: save the session if configured, start syncing, and open the room list. If login fails, the client SHALL show the server's error message.

#### Scenario: Successful SSO login
- **WHEN** the `m.login.token` exchange succeeds
- **THEN** the client is logged in as the `user_id` from the response
- **AND** syncing starts and the room list opens

#### Scenario: Token exchange rejected
- **WHEN** the `m.login.token` exchange returns an error such as `M_FORBIDDEN`
- **THEN** the client shows the error message and is not logged in
