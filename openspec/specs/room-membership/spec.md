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

### Requirement: Live self-removal behavior is preserved
The client SHALL show the removal dialog and remove the room when a `leave` or `ban` membership event for the current user is received outside history pagination.

#### Scenario: Live self-leave
- **WHEN** a `leave` event for the current user is received through sync
- **THEN** a dialog describing the removal is shown
- **AND** the room is removed from the room list after the dialog is acknowledged

#### Scenario: Another user's historical leave
- **WHEN** a history page contains a `leave` event for a different user
- **THEN** no dialog is shown
- **AND** the room remains in the room list
