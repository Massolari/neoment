# Spec Delta

## Purpose

Lets the user view and change the notification settings stored on their Matrix account as push rules, both the global defaults and per-room settings, so they stay in sync with other Matrix clients.

## ADDED Requirements

### Requirement: Push rules follow the account
The client SHALL keep the account's push rules as received from the homeserver, and SHALL replace them whenever a sync delivers a new version, including changes made from other clients. When the push rules have not been received yet, opening a notification settings window SHALL request them from the homeserver first.

#### Scenario: Changed in another client
- **GIVEN** a room is set to "None" in Element
- **WHEN** the next sync delivers the updated push rules and the user opens the room's notification settings in Neoment
- **THEN** "None" is shown as the room's current setting

#### Scenario: Window opened before the rules arrived
- **GIVEN** the client has not received the push rules in a sync yet
- **WHEN** the user opens a notification settings window
- **THEN** the client requests the push rules from the homeserver and shows the window with them

#### Scenario: Push rules cannot be loaded
- **GIVEN** the client has no push rules and the request for them fails
- **WHEN** the user opens a notification settings window
- **THEN** an error naming the failure is shown and no window opens

### Requirement: Global notification levels
The client SHALL derive a global level for **One-to-one rooms** and one for **Group rooms**: "All messages" when that category's message rule is enabled and notifies, otherwise "Mentions and replies only". One-to-one rooms SHALL be rooms with exactly two joined members, as the server's rule decides, regardless of whether Neoment lists the room as a direct message.

#### Scenario: Default server rules
- **GIVEN** the account has the server-default push rules
- **WHEN** the global levels are derived
- **THEN** both One-to-one rooms and Group rooms are "All messages"

#### Scenario: Group message rule does not notify
- **GIVEN** the group message rule is enabled with no notify action
- **WHEN** the global levels are derived
- **THEN** Group rooms is "Mentions and replies only"

#### Scenario: One-to-one rule disabled
- **GIVEN** the one-to-one message rule is disabled
- **WHEN** the global levels are derived
- **THEN** One-to-one rooms is "Mentions and replies only"

#### Scenario: Room with three members marked as direct
- **GIVEN** a room is marked as direct but has three joined members
- **WHEN** the global level that applies to the room is derived
- **THEN** the Group rooms level applies

#### Scenario: Two-member room not marked as direct
- **GIVEN** a room is not marked as direct and has two joined members
- **WHEN** the global level that applies to the room is derived
- **THEN** the One-to-one rooms level applies

#### Scenario: Neoment direct toggle
- **GIVEN** a room with three joined members applies the Group rooms level
- **WHEN** the user marks it as direct with the room list's direct toggle
- **THEN** the Group rooms level still applies

### Requirement: Room notification levels
The client SHALL derive a room's level from the push rules: "None" when an enabled override rule for exactly that room does not notify; else "All messages" or "Mentions and replies only" when an enabled room rule for it notifies or does not; else "Global settings".

#### Scenario: No rule for the room
- **GIVEN** the push rules contain no rule for the room
- **WHEN** the room level is derived
- **THEN** the level is "Global settings"

#### Scenario: Room rule that notifies
- **GIVEN** an enabled room rule for the room has a notify action
- **WHEN** the room level is derived
- **THEN** the level is "All messages"

#### Scenario: Room rule that does not notify
- **GIVEN** an enabled room rule for the room has no notify action
- **WHEN** the room level is derived
- **THEN** the level is "Mentions and replies only"

#### Scenario: Mute override
- **GIVEN** an enabled override rule matches only that room and has no notify action
- **AND** a room rule for the room notifies
- **WHEN** the room level is derived
- **THEN** the level is "None"

#### Scenario: Disabled rules ignored
- **GIVEN** the only rule for the room is a disabled room rule
- **WHEN** the room level is derived
- **THEN** the level is "Global settings"

### Requirement: Changing a global level
Setting a global level SHALL update on the homeserver both the plain and the encrypted message rule of that category, enabling them with a notify action for "All messages" or with no notify action for "Mentions and replies only". Mention, keyword and per-room rules SHALL NOT be changed.

#### Scenario: Group rooms to mentions only
- **WHEN** the user sets Group rooms to "Mentions and replies only"
- **THEN** the group message rule and the encrypted group message rule are enabled with no notify action
- **AND** the user mention rules are unchanged

#### Scenario: One-to-one rooms to all messages
- **GIVEN** the one-to-one message rule is disabled
- **WHEN** the user sets One-to-one rooms to "All messages"
- **THEN** the one-to-one and encrypted one-to-one rules are enabled with a notify action

### Requirement: Changing a room level
Setting a room level SHALL leave on the homeserver only the rules for that room that express the new level: no rule for "Global settings"; a room rule that notifies for "All messages"; a room rule that does not notify for "Mentions and replies only"; an override rule matching only that room, with no notify action, for "None".

#### Scenario: Mute a room
- **WHEN** the user sets a room to "None"
- **THEN** an override rule matching only that room with no notify action exists on the homeserver

#### Scenario: Unmute to all messages
- **GIVEN** a room is set to "None"
- **WHEN** the user sets it to "All messages"
- **THEN** the room's override rule is removed and a room rule with a notify action exists

#### Scenario: Back to global settings
- **GIVEN** a room is set to "Mentions and replies only"
- **WHEN** the user sets it to "Global settings"
- **THEN** no override or room rule for that room remains

### Requirement: Failed changes are reported
When the homeserver rejects or fails a settings change, the client SHALL show an error naming the failure, SHALL keep the window open, and SHALL show the level the push rules hold after the attempt.

#### Scenario: Request fails
- **GIVEN** a room is set to "Global settings"
- **WHEN** the user picks "None" and the homeserver answers with an error
- **THEN** an error is shown and the window still marks "Global settings" as current

### Requirement: Global notification settings window
In the room list, `<localleader>n` (`<Plug>NeomentRoomsNotificationSettings`) SHALL open a floating window listing the levels of "One-to-one rooms (2 members)" and "Group rooms (3+ members)", each with "All messages" and "Mentions and replies only" and the current one marked. `<CR>` on an option SHALL apply it and update the marks. `q` or `<Esc>` SHALL close the window.

#### Scenario: Open from the room list
- **WHEN** the user presses `<localleader>n` in the room list
- **THEN** a window shows both categories with their current levels marked

#### Scenario: Choose an option
- **GIVEN** the global window is open and Group rooms is "All messages"
- **WHEN** the user moves to "Mentions and replies only" under Group rooms and presses `<CR>`
- **THEN** the change is sent to the homeserver and "Mentions and replies only" becomes the marked option

#### Scenario: Close
- **WHEN** the user presses `q` in the global window
- **THEN** the window closes without changing any setting

### Requirement: Room notification settings window
`<localleader>N` SHALL open a floating window titled with the room's name for the room under the cursor in the room list (`<Plug>NeomentRoomsRoomNotificationSettings`) or the room of a room buffer (`<Plug>NeomentRoomRoomNotificationSettings`). It SHALL list "Global settings (<global level that applies to the room>)", "All messages", "Mentions and replies only" and "None", with the current one marked, and use the same keys as the global window.

#### Scenario: Open from the room list
- **GIVEN** the cursor is on a group room whose level is "Global settings" and Group rooms is "Mentions and replies only"
- **WHEN** the user presses `<localleader>N`
- **THEN** the window shows "Global settings (Mentions and replies only)" as the marked option

#### Scenario: Open from a room buffer
- **WHEN** the user presses `<localleader>N` in a room buffer
- **THEN** the window shows the settings of that buffer's room

#### Scenario: No room under the cursor
- **GIVEN** the cursor is on a section header in the room list
- **WHEN** the user presses `<localleader>N`
- **THEN** no window opens and a message says no room is under the cursor

#### Scenario: Invited room
- **GIVEN** the cursor is on a room the user is only invited to
- **WHEN** the user presses `<localleader>N`
- **THEN** no window opens and a message says notification settings are available after joining

#### Scenario: Global level changes the label
- **GIVEN** a group room is on "Global settings" and the global window sets Group rooms to "All messages"
- **WHEN** the user opens that room's notification settings
- **THEN** the first option reads "Global settings (All messages)"

### Requirement: Custom source notice in the windows
When `desktop_notifications.source` is `"custom"`, both windows SHALL still show and change the server settings, and SHALL show a line saying that Neoment's desktop notifications currently follow the `desktop_notifications` config instead.

#### Scenario: Window under the custom source
- **GIVEN** the source is `"custom"`
- **WHEN** the user opens either notification settings window
- **THEN** the window shows the server settings and the notice about the config
