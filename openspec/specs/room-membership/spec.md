# room-membership Specification

## Purpose

Defines how the client reacts to the current user's own membership events, so that old history never changes which rooms the user appears to be joined to.

## Requirements

### Requirement: Historical self-removal does not remove the room
The client SHALL NOT show a removal dialog or remove the room from the room list when a `leave` or `ban` membership event for the current user is received through history pagination.

#### Scenario: Paginated chunk contains an old self-leave
- **GIVEN** the user is joined to a room
- **WHEN** a history page's timeline chunk contains a `leave` event for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list

#### Scenario: Paginated chunk contains an old self-ban
- **GIVEN** the user is joined to a room
- **WHEN** a history page's timeline chunk contains a `ban` event for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list

#### Scenario: Paginated state contains an old self-leave
- **GIVEN** the user is joined to a room
- **WHEN** a history page's accompanying state contains a `leave` event for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list

#### Scenario: Paginated chunk contains a leave and rejoin sequence
- **GIVEN** the user is joined to a room
- **WHEN** a history page contains a `leave`, an `invite` and a `join` event for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list

### Requirement: Historical membership events remain visible
The client SHALL render membership events received through history pagination as membership lines in the room timeline.

#### Scenario: Old self-leave is rendered
- **WHEN** a history page contains a `leave` event for the current user
- **THEN** the room timeline includes a membership line for that event

### Requirement: Rooms left according to sync are removed
The client SHALL remove every room listed in the sync response's left-rooms section from the room list, whether the room was joined or invited.

#### Scenario: User is kicked from a joined room
- **GIVEN** the user is joined to a room
- **WHEN** an incremental sync lists the room as left
- **THEN** the room is removed from the room list

#### Scenario: Invite is rejected or revoked
- **GIVEN** the user has a pending invite to a room
- **WHEN** an incremental sync lists the room as left
- **THEN** the invite is removed from the room list

#### Scenario: Unknown room is listed as left
- **GIVEN** the client has no record of a room
- **WHEN** a sync lists that room as left
- **THEN** no dialog is shown
- **AND** the room does not appear in the room list

### Requirement: Removal by another user is announced
The client SHALL show a dialog describing the removal when an incremental sync lists a known room as left and the current user's membership event for it was sent by another user. The room SHALL be removed after the dialog is acknowledged.

#### Scenario: User is kicked
- **GIVEN** the user is joined to a room
- **WHEN** an incremental sync lists the room as left with a `leave` event for the current user sent by another user
- **THEN** a dialog stating that the user was removed from the room is shown
- **AND** the room is removed from the room list after the dialog is acknowledged

#### Scenario: User is banned
- **GIVEN** the user is joined to a room
- **WHEN** an incremental sync lists the room as left with a `ban` event for the current user
- **THEN** a dialog stating that the user was banned from the room is shown
- **AND** the room is removed from the room list after the dialog is acknowledged

#### Scenario: Left room has no membership event for the user
- **GIVEN** the user is joined to a room
- **WHEN** an incremental sync lists the room as left without a membership event for the current user
- **THEN** no dialog is shown
- **AND** the room is removed from the room list

### Requirement: Self-initiated leave is silent
The client SHALL NOT show a dialog when a room is listed as left and the current user's membership event for it was sent by the current user.

#### Scenario: User leaves with the leave command
- **GIVEN** the user left a room through the plugin's leave command
- **WHEN** the next sync lists the room as left with the user's own `leave` event
- **THEN** no dialog is shown
- **AND** the room is removed from the room list

#### Scenario: User rejects an invite
- **GIVEN** the user has a pending invite to a room
- **WHEN** a sync lists the room as left with the user's own `leave` event
- **THEN** no dialog is shown
- **AND** the invite is removed from the room list

### Requirement: Initial sync removes left rooms silently
The client SHALL NOT show removal dialogs for rooms listed as left in a sync made without a since token. Those rooms SHALL still be removed.

#### Scenario: Initial sync lists a room the user was kicked from
- **GIVEN** the client has a room in its list
- **WHEN** a sync without a since token lists the room as left with a `leave` event sent by another user
- **THEN** no dialog is shown
- **AND** the room is removed from the room list

### Requirement: Self-removal events in joined rooms do not remove the room
The client SHALL NOT show a removal dialog or remove the room when a `leave` or `ban` event for the current user is received for a room that the sync lists as joined. The event SHALL still update the member list and be rendered as a membership line.

#### Scenario: Leave and rejoin within one sync
- **GIVEN** the user is joined to a room
- **WHEN** a sync lists the room as joined and its timeline contains a `leave` followed by a `join` for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list

#### Scenario: Old self-leave in joined room state
- **GIVEN** the user is joined to a room
- **WHEN** a sync lists the room as joined and its state contains a `leave` event for the current user
- **THEN** no dialog is shown
- **AND** the room remains in the room list
