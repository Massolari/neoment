# Tasks

## 1. Client room removal

- [x] 1.1 Delete the second `M.remove_room` definition in `lua/neoment/matrix/client.lua` so the remaining one clears both `rooms` and `invited_rooms`. Verify with a test that `remove_room` on an invited room makes `client.is_invited_room` return false and `client.has_room` stay false.

## 2. Stop removing rooms from member events

- [x] 2.1 Export `member_state_event_to_message` from `lua/neoment/matrix/event.lua` as `M.member_event_to_message`, keeping the local call site working. Verify `devbox run test` still passes.
- [x] 2.2 Remove the self-removal block (current-user check, `vim.fn.confirm` dialog, `client.remove_room`, `update_room_list`) from the `m.room.member` branch of `event.handle`, keeping `remove_room_member` and message insertion. Update the `is_history` doc comments to drop the removal rationale. Verify that the existing historical tests in `tests/matrix_event_membership_spec.lua` still pass.
- [x] 2.3 Replace the "live events" test ("shows the dialog and removes the room for a self leave") with tests for a non-history self `leave` and a self `ban` passed to `event.handle_multiple`: no dialog, room kept, membership line rendered. Add a leave → join sequence and a leave-in-state case. Verify that `devbox run test` passes.

## 3. Process `rooms.leave` in sync

- [x] 3.1 In `lua/neoment/matrix/init.lua`, add `handle_sync_left_rooms(left_rooms, is_initial)` per design.md. It must skip unknown rooms without calling `get_room`/`get_invited_room`, find the user's latest `m.room.member` event (timeline from the end, then state), capture the display name, call `client.remove_room`, schedule the dialog only when not initial and `sender ~= user_id`, and schedule one `update_room_list` per sync. Verify by running the tests from 3.3.
- [x] 3.2 In `M.sync`, compute `is_initial` from `client.client.sync_token == nil` before it is overwritten, and call the new handler when `sync_data.rooms.leave` is present. Verify by running the tests from 3.3.
- [x] 3.3 Add a `describe("sync rooms.leave")` block to `tests/matrix_event_membership_spec.lua` that stubs `neoment.matrix.api.get` to return a canned sync response and calls `matrix.sync`. Cover a kick (dialog shown, room removed), a ban (dialog shown, room removed), a self leave (no dialog, room removed), a rejected invite (no dialog, invite removed), an unknown room (no dialog, `has_room` false afterwards), an initial sync with no `sync_token` (no dialog, room removed), and a left room with no self membership event (no dialog, room removed). Verify that `devbox run test` passes.

## 4. Integration check

- [ ] 4.1 Manually verify against a homeserver. Kick the user from a second account: the dialog appears and the room leaves the list. Leave a room with the plugin's leave command: no extra dialog, and the room leaves the list after the next sync. Restart neoment after being kicked while it was closed: the room is removed on the first sync. Record the results in the PR description.
