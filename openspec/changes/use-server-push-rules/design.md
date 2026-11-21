# Design

## Context

- `notify.desktop_message(room, message)` (`lua/neoment/notify.lua`) runs for every message passed to `client.add_room_message`, and decides from `desktop_notifications.{buffer,per_room,favorites,people,rooms}`. It already skips the first sync, the user's own messages and state events, and the focused room.
- `handle_sync_joined_rooms` (`lua/neoment/matrix/init.lua`) processes account data, timeline, state and ephemeral events, and only then copies `unread_notifications.notification_count`/`highlight_count` into `room.unread_notifications`/`room.unread_highlights`. These counts are persisted in the session cache (`storage.get_stripped_room`).
- `handle_sync_account_data` only handles `m.direct`; `m.push_rules` is ignored.
- The sync filter limits timelines to 1 event per room, and untracked rooms keep only their latest message, so a sync rarely carries every new message.
- The room summary (`m.joined_member_count`) is read only to name rooms and is not stored; members are lazy-loaded, so `room.members` is not a reliable count.
- Floating windows are built inline (e.g. the event viewer in `room.lua`: centered, `relative = "editor"`, rounded border, `q` closes). Mappings go through `util.get_plug_mapping_setter` in `after/ftplugin/*.lua`.

## Goals / Non-Goals

**Goals:**
- Server source needs no local push rule evaluation: the server-computed counts are the signal.
- The settings windows produce the same push rules Element produces, so either client reads the other's settings.
- One module owns push-rule interpretation and the windows (`lua/neoment/notification_settings.lua`); `notify.lua` owns the notification decision.

**Non-Goals:**
- Keyword rules, @room/display-name mention toggles, sounds, and per-device push (pushers).
- Notification counts or badges in the room list beyond what exists today.
- Thread-specific notification counts (`unread_thread_notifications`).
- Migrating custom levels into server push rules.

## Decisions

### 1. Server source is driven by count increases, not by evaluating rules
In `handle_sync_joined_rooms`, read the room's previous `unread_notifications`/`unread_highlights` before overwriting them, then call `notify.room_counts_changed(room, old, new)` after the counts are stored. It sends one notification when either count went up.
- *Alternative*: evaluate push rules per event locally. Rejected (user choice): much more code (conditions, display-name matching, power levels), and it can disagree with the server.
- Counts from a sync that has no `unread_notifications` key are left unchanged, so they never look like an increase.

### 2. The notification shows the newest incoming message seen in this sync
`notify.desktop_message` keeps its custom-source logic. With the server source, it records the message as the room's notification candidate when the sender is not the user and the message is not a state event (`candidates[room_id] = message`, newest timestamp wins), and sends nothing. `room_counts_changed` uses and clears the candidate. If there is none, it falls back to the newest stored message from another user that is newer than the user's read receipt and than the message of the room's last notification, then to room name + "New notification". All candidates are cleared at the start and at the end of `matrix.sync`'s response handling, so messages loaded by pagination are not candidates and a stale message is never shown later. The candidates and the last notified timestamps belong to the current client, and start empty when it is replaced (logout, new login).
- This works for untracked rooms, which keep only one message, because the candidate is captured as each message is added.
- Title and body formatting are shared with the custom path (a `format_title(room, sender)` helper extracted from the current code).

### 3. Source selection in config
Add `desktop_notifications.source` (`"server"|"custom"`, default `"server"`) to the config types and defaults, validated in `config.load` like `login_method`. The legacy warning checks the raw `vim.g.neoment` (before merging defaults) for any of `buffer`, `favorites`, `people`, `rooms`, `per_room` with no `source`. A module-level flag keeps it to one warning per Neovim session. `enabled` and `handler` are shared by both sources; the shared skip checks (disabled, first sync, focused room) move into one helper used by both paths.

### 4. Push rules storage and loading
- `handle_sync_account_data` stores the content of an `m.push_rules` event on `client.client.push_rules` (the ruleset object `{ global = { override, content, room, sender, underride } }`). Since it lives on the client, logout and `set_homeserver` drop it.
- Push rules are not stored in the session cache. After a restore, an incremental sync only sends them when they change, so `notification_settings` loads them with `GET /_matrix/client/v3/pushrules/` when it opens a window without them, and stores the result the same way.
- New functions in `matrix/init.lua`: `fetch_push_rules(cb)`, `set_push_rule(kind, rule_id, body, cb)`, `delete_push_rule(kind, rule_id, cb)`, `set_push_rule_actions(kind, rule_id, actions, cb)` and `set_push_rule_enabled(kind, rule_id, enabled, cb)`, on `api.authed`. Rule IDs are URL-encoded (room IDs contain `!` and `:`).

### 5. Level mapping (Element-compatible)
"Notifies" means the rule's `actions` contains `"notify"`. Legacy `"dont_notify"` and `[]` both count as not notifying. Writes use `[]` (current spec form). Writes that notify keep the sound tweak Element and the server defaults use: room rules and the one-to-one rules get `["notify", {set_tweak: "sound", value: "default"}]`, the group rules get `["notify"]`.

| Level | Push rules |
|---|---|
| Room: Global settings | no `override` or `room` rule with `rule_id == room_id` |
| Room: All messages | `room` rule `room_id`, actions `["notify", {set_tweak: "sound", value: "default"}]` (Element only shows a room rule as "All messages" when it has a sound) |
| Room: Mentions and replies only | `room` rule `room_id`, actions `[]` |
| Room: None | `override` rule `room_id`, conditions `[{kind="event_match", key="room_id", pattern=room_id}]`, actions `[]` |
| Global one-to-one rooms | `.m.rule.room_one_to_one` + `.m.rule.encrypted_room_one_to_one` (underride) |
| Global groups | `.m.rule.message` + `.m.rule.encrypted` (underride) |

- Reading a room override as "None" requires it to be enabled, have that single `event_match room_id` condition, and not notify. Any other override with that ID is ignored, so other clients' rules are not misread.
- Global writes use the `/actions` and `/enabled` endpoints, because server-default (`.`-prefixed) rules cannot be created or deleted. A rule missing from the current ruleset (e.g. an older server without the encrypted rule) is skipped.
- "Mentions and replies only" relies on the server's mention rules: replies carry the replied-to sender in `m.mentions`, which `.m.rule.is_user_mention` matches.
- Replacing an existing rule with `PUT` keeps its enabled flag, so a room write also enables the rule it replaces when the local ruleset has it disabled.
- Room writes create the new rule first and then delete the obsolete ones, so a failure part-way leaves the room on a deliberate setting rather than briefly on "Global settings". Deletes are only sent for rules present in the local ruleset, to avoid 404s.
- After the requests finish, successful or not, the module re-fetches the push rules and re-renders, so the window shows the real server state (spec: "Failed changes are reported").

### 6. Which global level applies to a room
Store `room.joined_member_count` from `summary["m.joined_member_count"]` whenever a sync includes it, and persist it in `get_stripped_room`. A room is one-to-one for push purposes when that count is 2. When the count is unknown (old cache), fall back to `room.is_direct` until a sync delivers the summary. This mirrors the server's `room_member_count == 2` condition. Neoment's DM flag (`m.direct` plus the local-only `<localleader>d` toggle) does not decide it. That is why the UI says "One-to-one rooms (2 members)" and "Group rooms (3+ members)" rather than "Direct messages": the rows should not suggest they follow Neoment's DM section.

### 7. Windows
- A centered float (`relative = "editor"`, `border = "rounded"`, title) on a scratch buffer with `bufhidden = "wipe"` and `modifiable = false`, rendered from a list of `{ text, action }` lines so `<CR>` looks up the action by cursor row. Header and notice lines have no action.
- Marks use `(•)` / `( )`, the room title comes from `matrix.get_room_display_name_with_space`, and the custom-source notice is a dimmed trailing line.
- `<CR>` on an option that is already current does nothing. While a change is in flight, further `<CR>` presses are ignored and the title shows "Saving…".
- `q`/`<Esc>` close. The buffer-local mappings are set inside the module, as the event viewer does, because the window is transient.
- Entry points: `notification_settings.open_global()` and `notification_settings.open_room(room_id)`. `rooms.lua` adds `M.open_room_notification_settings()` using `get_room_mark_under_cursor()` (rejecting invited rooms via `matrix.has_invited_room`); `room.lua` passes `vim.b[buf].room_id`.
- Mappings: `NeomentRoomsNotificationSettings` (`<localleader>n`) and `NeomentRoomsRoomNotificationSettings` (`<localleader>N`) in `after/ftplugin/neoment_rooms.lua`; `NeomentRoomRoomNotificationSettings` (`<localleader>N`) in `after/ftplugin/neoment_room.lua`. None of these keys is taken in those buffers.

## Risks / Trade-offs

- [The timeline limit of 1 means the candidate can be the user's own message, or absent, when several messages arrive in one sync] → Fall back to the newest stored message from another user, then "New notification"; the user is still told something arrived.
- [Counts only reach a sync after the server processes the event, so a notification can lag by one sync] → Acceptable; it is at most one long-poll cycle.
- [Reading a room in another client lowers the count; a new message in the same sync could leave the count equal and suppress the notification] → Rare, and matching the server's view is the point of this source. Documented in the README.
- [Changing the default source silently changes behavior for users with custom levels] → One-time warning plus a **BREAKING** note in the README.
- [Partial failure of a multi-request change] → Create-then-delete ordering, plus a re-fetch so the window shows the true state.
- [`room.joined_member_count` unknown for rooms restored from an old cache] → Fall back to `is_direct` until a sync delivers the summary.

## Migration Plan

- No data migration. Users who want the old behavior add `source = "custom"`, and the warning tells them so.
- Rollback: setting `source = "custom"` restores the previous decisions exactly. Push rules written by the windows stay on the server and are the same as Element's.
