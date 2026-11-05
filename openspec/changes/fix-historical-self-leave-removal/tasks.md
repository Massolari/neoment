# Tasks

## 1. Event handler

- [x] 1.1 Create `tests/matrix_event_membership_spec.lua` following the module reset pattern in `tests/matrix_room_avatar_spec.lua`, with `vim.fn.confirm` stubbed, `neoment.rooms` stubbed, `client.client.user_id` set and `display_names` seeded, and with scheduled callbacks flushed through `vim.wait`. Add failing cases for a historical self-`leave`, self-`ban` and `leave`/`invite`/`join` sequence, and verify with `devbox run test` that they fail on the missing flag.
- [x] 1.2 Add an optional `is_history` parameter with an `@param` annotation to `M.handle` in `lua/neoment/matrix/event.lua`, and skip the self-removal flow when it is set. Keep `remove_room_member` and the membership message as they are. Verify that the 1.1 cases pass.
- [x] 1.3 Add an optional `is_history` parameter with an `@param` annotation to `M.handle_multiple`, forwarding it to `M.handle` and to the recursive pending events call. Verify with a test that a pending event released by a historical event is processed with the flag set.
- [x] 1.4 Add tests that a historical self-`leave` still adds its membership line to `room.messages`, that a self-`leave` without the flag still calls `vim.fn.confirm` and removes the room, and that another user's historical `leave` triggers neither. Verify with `devbox run test`.

## 2. History pagination

- [x] 2.1 Add a failing test that calls `matrix.load_more_messages` with `api.get` stubbed to return a self-`leave`, once in `chunk` and once in `state.events` alongside a non-empty `chunk`, and asserts no dialog and that the room remains. Verify that it fails before 2.2.
- [x] 2.2 Pass `true` as `is_history` from the `event.handle_multiple` call in `M.load_more_messages` in `lua/neoment/matrix/init.lua`. Verify that the 2.1 test and the full suite pass with `devbox run test`.

## 3. Manual check

- [ ] 3.1 In Neovim, open a joined room whose history contains an old self-leave and paginate past it. Verify that no dialog appears, the membership line is shown, and the room stays in the room list.
