# Spec Delta

## Purpose

Decides when Neoment sends a desktop notification for a new message, either following the Matrix account's push rules as evaluated by the homeserver or following the levels set in the Neoment config.

## ADDED Requirements

### Requirement: Notification source selection
The client SHALL decide desktop notifications from the source set in `desktop_notifications.source`: `"server"` follows the account's push rules, `"custom"` follows the Neoment config levels. When the option is not set, the source SHALL be `"server"`. Any other value SHALL be rejected with a configuration error naming the accepted values.

#### Scenario: Source not set
- **GIVEN** the config does not set `desktop_notifications.source`
- **WHEN** a new message arrives
- **THEN** the client decides the notification with the server source

#### Scenario: Custom source chosen
- **GIVEN** the config sets `desktop_notifications.source = "custom"`
- **WHEN** a new message arrives
- **THEN** the client decides the notification with the custom source

#### Scenario: Invalid source
- **WHEN** the config sets `desktop_notifications.source = "push"`
- **THEN** loading the config fails with an error that names `"server"` and `"custom"`

### Requirement: Warning for custom levels under the default source
The client SHALL show a warning, once per Neovim session, when the config sets any of `buffer`, `favorites`, `people`, `rooms` or `per_room` under `desktop_notifications` but does not set `source`. The warning SHALL say that these levels are ignored and that `source = "custom"` restores them.

#### Scenario: Legacy levels without a source
- **GIVEN** the config sets `desktop_notifications.rooms = "all"` and no `source`
- **WHEN** the config is loaded
- **THEN** a warning says the custom levels are ignored and how to enable them

#### Scenario: Legacy levels with an explicit source
- **GIVEN** the config sets `desktop_notifications.rooms = "all"` and `source = "server"`
- **WHEN** the config is loaded
- **THEN** no warning is shown

#### Scenario: Config reloaded
- **GIVEN** the warning was already shown in this Neovim session
- **WHEN** the config is loaded again with the same settings
- **THEN** the warning is not shown again

### Requirement: Server source notifies when the room's notification count goes up
With the server source, the client SHALL send one desktop notification for a room when a sync reports a higher unread notification count or a higher highlight count for that room than the client had before. Unchanged or lower counts SHALL NOT send a notification. The custom levels SHALL be ignored.

#### Scenario: Count increases
- **GIVEN** a room has a notification count of 2
- **WHEN** a sync reports a notification count of 3 for that room
- **THEN** one desktop notification is sent for that room

#### Scenario: Several messages in one sync
- **GIVEN** a room has a notification count of 0
- **WHEN** a sync reports a notification count of 4 for that room
- **THEN** exactly one desktop notification is sent for that room

#### Scenario: Message that the push rules do not notify
- **GIVEN** the user's push rules do not notify for a message
- **WHEN** a sync delivers that message and the room's notification count does not change
- **THEN** no desktop notification is sent

#### Scenario: Room read in another client
- **GIVEN** a room has a notification count of 5
- **WHEN** a sync reports a notification count of 0 for that room
- **THEN** no desktop notification is sent

#### Scenario: Only the highlight count increases
- **GIVEN** a room has a notification count of 1 and a highlight count of 0
- **WHEN** a sync reports a notification count of 1 and a highlight count of 1
- **THEN** one desktop notification is sent for that room

#### Scenario: Custom levels set with the server source
- **GIVEN** the source is `"server"` and `desktop_notifications.per_room` sets a room to `"none"`
- **WHEN** a sync reports a higher notification count for that room
- **THEN** a desktop notification is sent

### Requirement: Server source notification content
A server-source notification SHALL show the newest message in the room that was not sent by the current user, using the same title and body format as custom-source notifications. When the client has no such message, it SHALL show the room name as the title and "New notification" as the body.

#### Scenario: Newest message from another user
- **GIVEN** a sync delivers messages from Alice then Bob in a group room
- **WHEN** the room's notification count increases
- **THEN** the notification shows Bob's message with the room name and Bob's display name in the title

#### Scenario: Newest message is the user's own
- **GIVEN** a sync delivers a message from Alice followed by one from the current user
- **WHEN** the room's notification count increases
- **THEN** the notification shows Alice's message

#### Scenario: No message available
- **GIVEN** the client has no message from another user for the room
- **WHEN** the room's notification count increases
- **THEN** the notification shows the room name and the text "New notification"

### Requirement: Notifications that are never sent
For both sources, the client SHALL NOT send a desktop notification when `desktop_notifications.enabled` is false, during the first sync of a session, or for the room shown in the current buffer while Neovim has focus.

#### Scenario: Notifications disabled
- **GIVEN** `desktop_notifications.enabled` is false
- **WHEN** a sync reports a higher notification count for a room
- **THEN** no desktop notification is sent

#### Scenario: First sync
- **GIVEN** the client has not completed a sync in this session
- **WHEN** the first sync reports notification counts above the cached ones
- **THEN** no desktop notification is sent

#### Scenario: Focused room
- **GIVEN** Neovim has focus and the current buffer shows a room
- **WHEN** a sync reports a higher notification count for that room
- **THEN** no desktop notification is sent

#### Scenario: Room open but Neovim unfocused
- **GIVEN** Neovim does not have focus and the current buffer shows a room
- **WHEN** a sync reports a higher notification count for that room
- **THEN** a desktop notification is sent

### Requirement: Custom source keeps the config levels
With the custom source, the client SHALL decide each new message from another user with the existing config levels: `buffer` for rooms open in a buffer (falling through when `"none"`), then `per_room` by room ID or alias, then `favorites`, `people` or `rooms` by room type, each being `"all"`, `"mentions"` or `"none"`.

#### Scenario: Favorite room set to all
- **GIVEN** the source is `"custom"` and `favorites = "all"`
- **WHEN** another user sends a message in a favorite room that is not open
- **THEN** a desktop notification is sent

#### Scenario: Group room set to mentions
- **GIVEN** the source is `"custom"` and `rooms = "mentions"`
- **WHEN** another user sends a message without mentioning the current user in a group room
- **THEN** no desktop notification is sent

#### Scenario: Per-room override
- **GIVEN** the source is `"custom"`, `rooms = "all"` and `per_room` sets the room's alias to `"none"`
- **WHEN** another user sends a message in that room
- **THEN** no desktop notification is sent

#### Scenario: Server push rules ignored
- **GIVEN** the source is `"custom"`, `rooms = "all"` and the room is set to "None" in its server notification settings
- **WHEN** another user sends a message in that group room
- **THEN** a desktop notification is sent
