# Design

## Context

See proposal.md (Why) for the problem. The relevant current state:

- `M.sync` in `lua/neoment/matrix/init.lua` sets `client.client.sync_token = sync_data.next_batch` before it processes rooms. After that point it can't tell whether the request carried a `since` token.
- `handle_sync_invited_rooms` and `handle_sync_joined_rooms` return lists of updated room IDs. `neoment.sync` passes them to `on_done`, and the room list is refreshed from there.
- The self-removal flow (dialog + `client.remove_room` + `rooms.update_room_list`, all inside `vim.schedule`) lives in the `m.room.member` branch of `event.handle` (`lua/neoment/matrix/event.lua:590`), gated by `not is_history`.
- `member_state_event_to_message` (local to `event.lua`) already produces the right text for kick, ban and leave. It has a side effect: it records the display name.
- `client.get_room` and `matrix.get_room_display_name` create a joined-room entry when the ID is unknown.
- `client.lua` defines `remove_room` twice. The later definition (line 436) wins and only clears `rooms`.
- Sessions are restored with their `sync_token` (`storage.restore_session`), so the first sync after a restart is incremental. A kick that happened while neoment was closed therefore arrives in `rooms.leave` on that sync.

## Goals / Non-Goals

**Goals:**
- One place that decides room removal: the `rooms.leave` handler.
- `event.handle` becomes free of room-removal side effects for all callers (sync join timeline, sync join state, pagination).

**Non-Goals:**
- Closing an open room buffer for a removed room. The current flow doesn't do this either. A follow-up can add it.
- Handling `rooms.knock`.
- Forgetting rooms server-side (`/forget`).
- Changing the sync filter. The default `include_leave: false` only affects the initial sync's history of old leaves. Incremental syncs always report new leaves.

## Decisions

### Handle `rooms.leave` in a new `handle_sync_left_rooms(left_rooms, is_initial)`
It follows the shape of the existing per-section handlers in `init.lua` and is called from `M.sync` after the `join` handler. `is_initial` is computed as `client.client.sync_token == nil` **before** the token is overwritten. The function must not call `client.get_room` or `client.get_invited_room`; it checks `client.has_room` / `client.is_invited_room` first.

For each room:
1. Skip if the client knows neither a joined nor an invited room with that ID.
2. Find the current user's latest `m.room.member` event: scan `timeline.events` from the end, then `state.events`.
3. Capture the room name while the room still exists, using `get_room_display_name`, which is safe at this point because the room exists.
4. Call `client.remove_room(room_id)` right away. The room disappears from the model in the same sync it was reported.
5. If not initial, a membership event was found, and `event.sender ~= user_id`, schedule the `vim.fn.confirm` dialog with the room name and message text, as the old flow did.
6. Refresh the list by calling `require("neoment.rooms").update_room_list()` inside `vim.schedule`, once per sync rather than once per room.

*Alternative considered:* feed the left room's timeline through `event.handle_multiple` with a "left" flag and keep removal inside the member branch. Rejected: it would recreate the room through `get_room`, process message events for a room we're discarding, and keep removal logic spread across two modules.

*Alternative considered:* remove only after the dialog is acknowledged, as the old flow does. Rejected: `vim.fn.confirm` blocks, and several kicks in one sync would leave stale rooms visible behind the dialog. Removing first and then announcing keeps the model consistent. The spec only requires that the room be gone after acknowledgement, and removing it earlier satisfies that.

### Decide kick vs. self-leave by `sender`
A membership event whose `sender` is the current user is a voluntary leave or a rejected invite. Anything else is a kick, a ban, or a revoked invite, and gets the dialog. A `ban` is always sent by someone else. This one check also keeps the plugin's own leave commands, which already show their own "Left room" notification, from showing a second warning.

### Expose the message builder
Export `member_state_event_to_message` from `event.lua` (e.g. as `M.member_event_to_message`) so the leave handler reuses the exact wording. Its display-name side effect is harmless here.

### Strip removal from the `m.room.member` branch
Delete the `user_id` check, the dialog and the removal from `event.handle`. Keep `client.remove_room_member` and the message insertion. The `is_history` parameter stays because `handle_multiple` threads it through and #41's tests rely on it, but nothing in the member branch reads it anymore. Its doc comment should drop the removal rationale.

### Fix `client.remove_room`
Delete the second definition (line 436) so the remaining one clears both `rooms` and `invited_rooms`. `matrix.remove_room` (init.lua:1492) aliases it and keeps working. `room.lua`'s "Not a known room" fallback benefits from this too.

## Risks / Trade-offs

- [The leave event isn't in the left room's timeline (gappy timeline with `limit = 1`)] → The handler also checks `state.events`. If neither has it, the room is removed without a dialog, as the spec allows.
- [A kicked room can't be told apart from a revoked invite, since both have another user as sender] → Both get a dialog, and the existing message text distinguishes them ("had their invite to the room revoked by …"). This is acceptable.
- [Behavior change: a stale self-`leave` under `rooms.join` no longer removes a room. If a server ever sent a real removal only that way, it would be missed] → Per the Matrix spec, a room's section reflects membership at the end of the sync window, so a real removal always appears under `rooms.leave`.
- [Several kicks in one sync open several blocking dialogs in a row] → Same as today's behavior per event. Acceptable for a rare event.
- [Tests stub `neoment.rooms`, and the new handler lives in `init.lua`] → Drive `M.sync` with a stubbed `neoment.matrix.api.get` that returns a canned sync response. The existing spec already stubs `neoment.curl`, `neoment.notify` and `neoment.rooms`.

## Migration Plan

No data migration is needed. Cached sessions keep working: any room the user was removed from while offline is reported in `rooms.leave` on the first incremental sync after restore and removed then. Rollback is a plain revert.
