## ADDED Requirements

### Requirement: Refresh credentials are captured at login
The client SHALL request a refresh token when logging in with a password, and SHALL retain the refresh token and the access-token expiry time from the login response when the homeserver provides them.

#### Scenario: Homeserver issues expiring credentials
- **WHEN** a login response contains `refresh_token` and `expires_in_ms`
- **THEN** the client records the refresh token and an expiry time of now plus `expires_in_ms`

#### Scenario: Homeserver issues non-expiring credentials
- **WHEN** a login response contains neither `refresh_token` nor `expires_in_ms`
- **THEN** the client behaves as before and never attempts a refresh

### Requirement: Refresh credentials are persisted
The saved session SHALL include the refresh token, the access-token expiry time and the refresh method, and a restored session SHALL resume refreshing with them.

#### Scenario: Session restored after the access token expired
- **GIVEN** a saved session whose access token has expired and which holds a refresh token
- **WHEN** the session is restored and the first request is made
- **THEN** the access token is refreshed and the request succeeds without asking the user to log in

#### Scenario: Rotated tokens are saved
- **WHEN** a refresh succeeds and returns a new access token or refresh token
- **THEN** the new values are written to the saved session before they are needed again

#### Scenario: Session saved by an earlier version
- **WHEN** a saved session has no refresh fields
- **THEN** it restores as a non-expiring session

#### Scenario: Session age limit
- **GIVEN** a saved session older than 7 days
- **WHEN** it holds a refresh token
- **THEN** it is restored
- **WHEN** it holds no refresh token
- **THEN** it is rejected as expired, as before

### Requirement: Access token is refreshed before it expires
When the expiry time is known, the client SHALL refresh the access token before sending a request if the token is expired or within 60 seconds of expiring.

#### Scenario: Token about to expire
- **GIVEN** the access token expires in 30 seconds
- **WHEN** a request is made
- **THEN** a refresh completes first and the request is sent with the new token

### Requirement: Access token is refreshed after a soft-logout response
When a request receives HTTP `401` with `errcode` `M_UNKNOWN_TOKEN` and `soft_logout` true, and a refresh token is held, the client SHALL refresh the token and retry the original request once with the new token.

#### Scenario: Expired token detected by the server
- **WHEN** a request returns `401 M_UNKNOWN_TOKEN` with `soft_logout: true`
- **THEN** the token is refreshed and the same request is sent again
- **AND** the caller receives the result of the retry

#### Scenario: Retry also fails with 401
- **WHEN** the retried request again returns `401`
- **THEN** it is not retried further and the caller receives that error

#### Scenario: Hard logout
- **WHEN** a request returns `401 M_UNKNOWN_TOKEN` without `soft_logout` true
- **THEN** no refresh is attempted and the session is treated as ended

### Requirement: Both refresh methods are supported
The client SHALL refresh through `POST /_matrix/client/v3/refresh` for sessions using the legacy method, and through the OAuth 2.0 token endpoint with `grant_type=refresh_token` for sessions using the OAuth method. The method SHALL be selected by the saved session, defaulting to legacy.

#### Scenario: Legacy refresh
- **WHEN** a legacy session refreshes
- **THEN** the client posts its refresh token to the homeserver `/refresh` endpoint and stores the returned `access_token`, `refresh_token` (if present) and `expires_in_ms`

#### Scenario: OAuth refresh
- **WHEN** an OAuth session refreshes
- **THEN** the client posts a form-encoded `grant_type=refresh_token` request with its refresh token and client id to the stored token endpoint, and stores the returned `access_token`, `refresh_token` and `expires_in`

### Requirement: Concurrent requests share one refresh
While a refresh is in progress, the client SHALL NOT start another; requests that need a fresh token SHALL wait for the in-progress refresh and then use its result.

#### Scenario: Several requests expire together
- **WHEN** three requests all find the token expired at the same time
- **THEN** exactly one refresh request is sent
- **AND** all three requests are sent with the new token

### Requirement: Sync survives token rotation
The `/sync` loop SHALL continue without data loss or user-visible error when the token is refreshed before or during a long-poll request, resuming from the last `since` token.

#### Scenario: Token expires during long-poll
- **GIVEN** a `/sync` long-poll is in flight
- **WHEN** it returns `401 M_UNKNOWN_TOKEN` with `soft_logout: true`
- **THEN** the token is refreshed and `/sync` is repeated with the same `since`
- **AND** no error notification is shown

### Requirement: Media authentication uses the current token
Media downloads and image displays SHALL authenticate with the access token current at the moment of use. Stored message and avatar data SHALL NOT contain an access token.

#### Scenario: Media opened after a refresh
- **GIVEN** a message with an image received before a token refresh
- **WHEN** the user opens the image after the refresh
- **THEN** the request carries the new token

### Requirement: Failed refresh ends the session
When a refresh is rejected by the server, the client SHALL stop syncing, clear the saved session and tell the user to log in again. A refresh that fails for a transient reason (network error, 5xx) SHALL NOT clear the session and SHALL be retried by the next request.

#### Scenario: Refresh token rejected
- **WHEN** a refresh returns `4xx` such as `M_UNKNOWN_TOKEN` or `invalid_grant`
- **THEN** syncing stops, the saved session is deleted and an error asks the user to log in again

#### Scenario: Network error during refresh
- **WHEN** a refresh fails because the homeserver is unreachable
- **THEN** the session is kept and the user is not asked to log in again
