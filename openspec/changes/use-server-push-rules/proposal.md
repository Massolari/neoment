# Proposal

## Why

Neoment decides desktop notifications from its own config (`desktop_notifications.buffer`, `favorites`, `people`, `rooms`, `per_room`), ignoring the notification settings the user already keeps on their Matrix account through push rules. So a room muted in Element still notifies in Neoment, and a setting changed in Neoment never reaches other clients. Matrix already computes which messages notify: the server evaluates the push rules and reports per-room `notification_count`/`highlight_count` in every sync. Neoment should follow that by default and let users view and change those settings from inside Neovim.

## What Changes

- New option `desktop_notifications.source`, either `"server"` (default) or `"custom"`.
  - `"server"`: a desktop notification is sent when a room's server-computed unread notification count goes up in a sync, so the user's Matrix push rules decide which messages notify.
  - `"custom"`: the current behavior, unchanged (`buffer`, `favorites`, `people`, `rooms`, `per_room`).
  - `enabled` and `handler` apply to both sources. Both sources still skip the first sync, the user's own messages and the room that is focused.
- **BREAKING**: the default source is `"server"`, so users who set the custom levels (`favorites`, `rooms`, `per_room`, ...) must set `source = "custom"` to keep them. Neoment shows a one-time warning when it finds custom levels in the config while `source` is not set.
- Neoment reads the account's push rules (`m.push_rules` global account data) from sync and keeps them up to date.
- New global notification settings window, opened with `<localleader>n` in the room list (`<Plug>NeomentRoomsNotificationSettings`). It shows and sets the default level for **Direct messages** and **Group rooms**: "All messages" or "Mentions and replies only", as in Element. Muting ("None") is a per-room choice, so a room's own setting always wins over the global one.
- New room notification settings window, opened with `<localleader>N` in the room list for the room under the cursor (`<Plug>NeomentRoomsRoomNotificationSettings`) and in a room buffer for that room (`<Plug>NeomentRoomRoomNotificationSettings`). It offers, like Element: "Global settings (<the global level that applies to this room>)", "All messages", "Mentions and replies only" and "None", with the current choice marked.
- Both windows always read and write the server push rules, whatever the source. When `source = "custom"`, the windows say that desktop notifications currently follow the Neoment config instead.
- README: document `source`, the two windows, the new mappings and the breaking default.

## Capabilities

### New Capabilities
- `desktop-notifications`: when Neoment sends a desktop notification for a new message, for both the server source (push-rule-based unread counts) and the custom source (config levels), and how the source is selected.
- `notification-settings`: reading the account's push rules, deriving the global and per-room notification levels from them, changing them on the server, and the global and room notification settings windows with their mappings.

### Modified Capabilities
<!-- None: no existing spec covers notifications. -->

## Impact

- `lua/neoment/notify.lua`: split `desktop_message` into the custom path and a new server path triggered by count increases.
- `lua/neoment/matrix/init.lua`: compare old and new `unread_notifications`/`unread_highlights` in `handle_sync_joined_rooms`; store `m.push_rules` from global account data in `handle_sync_account_data`; add push rule API functions (`PUT`/`DELETE /_matrix/client/v3/pushrules/global/{kind}/{ruleId}` and `.../actions`).
- `lua/neoment/matrix/client.lua`: client state for the push rules (cleared on logout with the rest of the client).
- New module `lua/neoment/notification_settings.lua`: level derivation, rule updates and the two floating windows.
- `lua/neoment/config.lua`: `source` option, validation, legacy-config warning.
- `after/ftplugin/neoment_rooms.lua`, `after/ftplugin/neoment_room.lua`, `lua/neoment/rooms.lua`: mappings and room-under-cursor lookup.
- `README.md`: config and mappings.
- Tests in `tests/` for the notification decision, level derivation, rule updates and config.
- No new dependencies. Changing settings needs network access to the homeserver's push rules API.
