## ADDED Requirements

### Requirement: Logout clears the in-memory session
After the server accepts a logout, the client SHALL discard all session state held in memory: access token, refresh token and expiry, user ID, sync token, rooms, display names and presence. It SHALL keep only the homeserver and device ID. Afterwards the client SHALL report that it is not logged in, so the next `:Neoment` shows the login prompt. When the logout fails, the session SHALL be left untouched.

#### Scenario: Successful logout
- **GIVEN** a logged-in client with joined rooms
- **WHEN** the server accepts the logout
- **THEN** the client is not logged in
- **AND** no rooms, access token, user ID or sync token remain in memory

#### Scenario: Logout then reopen
- **WHEN** the user logs out and runs `:Neoment` again
- **THEN** the login prompt is shown instead of the room list

#### Scenario: Next login keeps the server
- **WHEN** the user logs in again after a logout
- **THEN** the client still targets the same homeserver and device ID

#### Scenario: Logout fails
- **WHEN** the server rejects the logout request
- **THEN** the access token, rooms and other session state remain in memory

#### Scenario: Logout fails keeps syncing
- **WHEN** the server rejects the logout request
- **THEN** synchronization keeps running for the unchanged session

#### Scenario: Sync response after the session ended
- **GIVEN** a sync request was in flight when the session ended
- **WHEN** its response arrives
- **THEN** it is discarded and does not touch the client
- **AND** it does not stop or restart a sync started for a new session
