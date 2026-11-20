# Spec Delta

## Purpose

Defines how the client logs in with the OAuth 2.0 device authorization grant against a homeserver that uses OAuth 2.0 (Matrix Authentication Service), and how it ends that session on logout.

## ADDED Requirements

### Requirement: OAuth server discovery
The client SHALL discover the OAuth server with `GET <homeserver>/_matrix/client/v1/auth_metadata` and treat the device authorization grant as supported only when the metadata lists `urn:ietf:params:oauth:grant-type:device_code` in `grant_types_supported` and provides `issuer`, `device_authorization_endpoint`, `token_endpoint` and `registration_endpoint` as HTTP(S) URLs.

#### Scenario: Server supports the device authorization grant
- **WHEN** the metadata lists the device code grant and provides all required endpoints
- **THEN** the client considers OAuth device login available

#### Scenario: Server does not list the device code grant
- **WHEN** `grant_types_supported` does not include `urn:ietf:params:oauth:grant-type:device_code`
- **THEN** the client considers OAuth device login unavailable

#### Scenario: Server has no auth metadata
- **WHEN** the request fails, returns an error status such as `404 M_UNRECOGNIZED`, or returns a body that is not a JSON object
- **THEN** the client considers OAuth device login unavailable and does not show an error

#### Scenario: Required endpoint is missing
- **WHEN** the metadata lacks the `registration_endpoint` or is missing any other required endpoint
- **THEN** the client considers OAuth device login unavailable

### Requirement: Client registration and reuse
The client SHALL register itself as a public native client with `POST <registration_endpoint>`, sending a client name, a client URI, the grant types `urn:ietf:params:oauth:grant-type:device_code` and `refresh_token`, `token_endpoint_auth_method: none` and `application_type: native`. It SHALL save the returned `client_id` per issuer and reuse it without registering again.

#### Scenario: First login on an issuer
- **GIVEN** no `client_id` is saved for the issuer
- **WHEN** OAuth device login starts
- **THEN** the client registers and saves the returned `client_id` for that issuer

#### Scenario: Later login on the same issuer
- **GIVEN** a `client_id` is saved for the issuer
- **WHEN** OAuth device login starts, including after logging out
- **THEN** the client reuses the saved `client_id` and sends no registration request

#### Scenario: Different issuer
- **GIVEN** a `client_id` is saved for another issuer
- **WHEN** OAuth device login starts on this issuer
- **THEN** the client registers again and saves a separate `client_id`

#### Scenario: Registration fails
- **WHEN** the registration request fails or the response has no `client_id`
- **THEN** the client shows an error that includes the server's message and does not log in

### Requirement: Device authorization request
The client SHALL request a device code with `POST <device_authorization_endpoint>`, form-encoded, with its `client_id` and the scope `urn:matrix:client:api:* urn:matrix:client:device:<device_id>`, where `<device_id>` is the client's device ID.

#### Scenario: Device code requested
- **WHEN** OAuth device login starts with a registered client
- **THEN** the request carries the `client_id` and a scope with both the API scope and the device scope

#### Scenario: Server rejects the client
- **WHEN** the device authorization request returns an error such as `invalid_client`
- **THEN** the client forgets the saved `client_id` for the issuer, shows the server's error and does not log in

### Requirement: Verification prompt
The client SHALL show the user the verification URL and user code from the device authorization response, using `verification_uri_complete` when present and `verification_uri` with `user_code` otherwise. It SHALL always show the user code, and in a local (non-SSH) session SHALL offer to open the URL with `vim.ui.open`.

#### Scenario: Server provides a complete verification URL
- **WHEN** the response contains `verification_uri_complete`
- **THEN** the client shows that URL and the user code

#### Scenario: Server provides only the base verification URL
- **WHEN** the response contains `verification_uri` and `user_code` but no `verification_uri_complete`
- **THEN** the client shows the URL and tells the user to enter the code there

#### Scenario: Local session
- **WHEN** the verification prompt is shown and the `SSH_CONNECTION` and `SSH_TTY` environment variables are not set
- **THEN** the client offers to open the URL in the browser, and polling continues whether or not the user accepts

#### Scenario: Remote session
- **WHEN** the verification prompt is shown and `SSH_CONNECTION` or `SSH_TTY` is set
- **THEN** the client does not try to open a browser and shows the URL and code for the user to use on any machine

### Requirement: Token polling
The client SHALL poll `token_endpoint` with the grant type `urn:ietf:params:oauth:grant-type:device_code`, the `device_code` and its `client_id` at the response's `interval` (5 seconds when absent), and SHALL stop when the login ends or the device code expires.

#### Scenario: Authorization pending
- **WHEN** the token endpoint answers `authorization_pending`
- **THEN** the client keeps polling at the same interval

#### Scenario: Slow down
- **WHEN** the token endpoint answers `slow_down`
- **THEN** the client increases the polling interval by 5 seconds and keeps polling

#### Scenario: Device code expires
- **WHEN** the token endpoint answers `expired_token`, or `expires_in` seconds pass without approval
- **THEN** the client stops polling, tells the user the code expired and does not log in

#### Scenario: User denies the login
- **WHEN** the token endpoint answers `access_denied`
- **THEN** the client stops polling, tells the user the login was denied and does not log in

#### Scenario: Temporary request failure
- **WHEN** a polling request fails because of a network error or a server error status
- **THEN** the client keeps polling until the device code expires

#### Scenario: Another login starts
- **WHEN** the user starts another login while the client is polling
- **THEN** the client stops polling and ignores any later result of the earlier attempt

### Requirement: OAuth session setup
When the token endpoint returns an access token, the client SHALL store it with the refresh token and expiry time, record the OAuth refresh method (token endpoint, `client_id` and revocation endpoint when advertised), and read the user ID with `GET /_matrix/client/v3/account/whoami`. It SHALL then continue as after any other login: save the session if configured, start syncing and open the room list.

#### Scenario: Login approved
- **WHEN** the token response contains `access_token`, `refresh_token` and `expires_in`
- **THEN** the client stores them, asks `whoami` for the user ID, and is logged in as that user
- **AND** the session saved afterwards holds the OAuth refresh method, so the access token is refreshed through the token endpoint

#### Scenario: Token response without a refresh token
- **WHEN** the token response contains an `access_token` and no `refresh_token`
- **THEN** the client logs in and treats the session as one that cannot be refreshed

#### Scenario: Whoami fails
- **WHEN** the `whoami` request fails
- **THEN** the client shows the error, revokes the new token when it can, and is not logged in

#### Scenario: Token response has no access token
- **WHEN** the token response is a success without an `access_token`
- **THEN** the client shows an error and is not logged in

### Requirement: Token revocation on logout
When the user logs out of an OAuth session, the client SHALL revoke the session's refresh token with `POST <revocation_endpoint>`, form-encoded with `token`, `token_type_hint` and `client_id`, instead of calling `/_matrix/client/v3/logout`. When the session has no revocation endpoint, the client SHALL use the regular logout request.

#### Scenario: Logout of an OAuth session
- **GIVEN** the session uses the OAuth refresh method with a revocation endpoint
- **WHEN** the user logs out
- **THEN** the client revokes the refresh token at that endpoint and ends the session once the server accepts it

#### Scenario: Revocation fails
- **WHEN** the revocation request fails
- **THEN** the client shows a logout error and keeps the saved session, as it does when the regular logout fails

#### Scenario: Session without a revocation endpoint
- **GIVEN** an OAuth session saved without a revocation endpoint
- **WHEN** the user logs out
- **THEN** the client sends `POST /_matrix/client/v3/logout`
