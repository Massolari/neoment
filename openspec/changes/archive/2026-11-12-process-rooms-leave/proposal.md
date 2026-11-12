# Proposal

## Why

Neoment never reads the `rooms.leave` section of `/sync`, so when the user is kicked or banned the room silently stays in the room list (issue #42). The only self-removal logic sits in the `m.room.member` handler, which only ever sees events under `rooms.join`. Those are stale by definition, because the server still reports the user as joined, so that logic fires in exactly the cases where it is wrong.

## What Changes

- Process `rooms.leave` from every sync response. Each listed room is removed from the client (joined or invited list) and the room list is refreshed.
- When the room was left because someone else removed the user (kick or ban), show the existing acknowledgement dialog describing the removal, built from the self membership event in the left room's timeline or state.
- When the user left on their own (the plugin's leave command, another device, a rejected invite), remove the room silently with no dialog. This prevents a warning on every normal leave, now that self-initiated leaves also arrive through `rooms.leave`.
- On the initial sync (no `since` token), remove rooms listed under `rooms.leave` silently, because that section can contain rooms left long ago.
- A `rooms.leave` entry for a room the client doesn't know must not create it.
- **BREAKING (behavior)**: a self `leave`/`ban` event received under `rooms.join` no longer shows a dialog or removes the room. It only updates the member list and renders the membership line.
- Fix the duplicate `client.remove_room` definition so removal clears both the joined and invited lists.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `room-membership`: the "Live self-removal behavior is preserved" requirement is replaced. Self-removal is now driven by the sync's `rooms.leave` section instead of by self membership events under `rooms.join`. New requirements cover kick/ban notification, silent self-initiated leaves, initial sync, unknown rooms, and ignoring stale self-removal events under `rooms.join`.

## Impact

- `lua/neoment/matrix/init.lua`: new `rooms.leave` handler in `M.sync`. It captures whether the request was initial before `sync_token` is overwritten.
- `lua/neoment/matrix/event.lua`: the self-removal flow is removed from the `m.room.member` branch. The membership message builder is exposed so the leave handler can reuse it.
- `lua/neoment/matrix/client.lua`: the duplicate `remove_room` is removed.
- `tests/matrix_event_membership_spec.lua`: the "live events" expectation flips, and new sync-level tests cover `rooms.leave`.
- No API, dependency or storage format changes. Leaving through the plugin's own commands now removes the room locally on the next sync. Before this change it stayed listed.
