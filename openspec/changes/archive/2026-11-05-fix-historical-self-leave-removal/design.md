# Design

## Context

`load_more_messages` (`lua/neoment/matrix/init.lua:688`) passes the `/messages` chunk and state events to `event.handle_multiple`, the same entry point sync uses. The `m.room.member` branch of `M.handle` (`lua/neoment/matrix/event.lua:589`) has no way to tell these sources apart, so it treats every self `leave` or `ban` as a removal that just happened.

Other callers of `handle_multiple` are the sync handlers and `refresh_room_state`, whose event type allowlist excludes `m.room.member`.

## Goals / Non-Goals

**Goals:**

- Stop history pagination from triggering the self-removal flow, as the issue proposes.
- Leave every non-pagination code path unchanged.

**Non-Goals:**

- **Stale self-leaves in sync responses.** A leave and rejoin inside one `rooms.join` timeline, or an old leave in its `state`, can still trigger the flow. This is inferred from reading the code and has not been reproduced.
- **Processing `rooms.leave`.** `handle_sync` only iterates `rooms.join` and `rooms.invite`, so kicks are not noticed through that section. The issue suggests this as a follow-up.
- **Other backfill side effects.** Backfilled events still update `room.members` (`add_room_member`, `remove_room_member`) and room properties such as name and topic, even when newer values exist. This includes removing the current user's own entry from `room.members`. This bug shares a root cause, but is a wider behavior change.

## Decisions

### Pass an `is_history` parameter through the handlers

Add an optional `is_history` boolean to `M.handle` and `M.handle_multiple`. `load_more_messages` passes `true`, and the self-removal check becomes `not is_history and event.state_key == user_id`. Omitting the argument keeps the live behavior, so sync callers need no edits.

`handle_multiple` forwards the flag when it recursively processes pending events, so events released by a backfilled event are still treated as historical. The `M.handle` call inside `handle_message` is not changed, because it only handles `m.replace` message events and never reaches the membership branch.

Alternatives considered:

- **Filter self `leave` and `ban` events out in `load_more_messages`:** rejected because the events would no longer be rendered.
- **Query the server for current membership before removing:** rejected because it adds a request and async handling to a path that only needs to know the event's source.

### Guard only the self-removal flow

The `remove_room_member` call before the check stays as it is, matching the issue's patch. See Non-Goals for why the wider membership problem is left out.

### Test at the handler and at the pagination call site

Handler tests cover the flag's behavior. One test drives `matrix.load_more_messages` with a stubbed `api.get`, because forgetting to pass the flag at the call site would otherwise leave the bug in place with all handler tests passing.

## Risks / Trade-offs

- [The spec's `state` field is only sometimes populated, and the request sets no filter] → The flag covers chunk and state events alike, so the fix doesn't depend on which of them carries the old event.
- [The live dialog path may rarely fire for real kicks, since those arrive in `rooms.leave`] → Behavior is kept as is. Whether to rework it belongs to the `rooms.leave` follow-up.
