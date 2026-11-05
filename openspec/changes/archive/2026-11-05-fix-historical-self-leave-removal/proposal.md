# Proposal

## Why

Paginating back through a room can reach an old `leave` or `ban` of the current user that a later rejoin has already superseded. Neoment treats that event as if the user had just been removed: it shows an "acknowledge" dialog and hides a room the user is still joined to, until the next restart (GitHub issue #41).

## What Changes

- Membership events received through history pagination no longer trigger the self-removal flow, so no dialog is shown and the room stays in the room list.
- Historical membership events are still rendered as membership lines in the room timeline.
- Events received through sync keep their current behavior, including the dialog and room removal.

## Capabilities

### New Capabilities

- `room-membership`: How the client reacts to the current user's membership events, depending on whether they arrive live or from paginated history.

### Modified Capabilities

None. The project has no existing specs.

## Impact

- `lua/neoment/matrix/event.lua`: `M.handle` and `M.handle_multiple` learn whether events are historical.
- `lua/neoment/matrix/init.lua`: `M.load_more_messages` marks its events as historical.
- `tests/`: new spec covering historical and live self-membership events.
- No new dependencies, and no changes to the Matrix API requests or to stored data.
