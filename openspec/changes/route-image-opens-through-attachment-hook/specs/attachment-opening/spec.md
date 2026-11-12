# Spec Delta

## Purpose

Defines how neoment opens downloaded media (message attachments, custom emoticons, custom reactions and room avatars), and guarantees that a single user-configurable handler controls every one of those open actions.

## ADDED Requirements

### Requirement: Message attachments open through the configured handler
When the user opens a message attachment, the client SHALL download it and call the configured `room.on_open_attachment` handler with the local path and the attachment's metadata, where `origin` is `"message"`.

#### Scenario: Opening an audio message attachment
- **GIVEN** a custom `room.on_open_attachment` handler is configured
- **WHEN** the user opens the attachment of an audio message
- **THEN** the handler is called once with the downloaded file's path
- **AND** the attachment argument has `type = "audio"` and `origin = "message"`

### Requirement: Custom emoticons open through the configured handler
When the user opens a custom emoticon under the cursor, the client SHALL download the image and call the configured `room.on_open_attachment` handler instead of opening the file directly.

#### Scenario: Opening a custom emoticon
- **GIVEN** a custom `room.on_open_attachment` handler is configured
- **AND** the cursor is on a custom emoticon in a room buffer
- **WHEN** the user triggers the open attachment action
- **THEN** the handler is called once with the downloaded image's path
- **AND** the attachment argument has `type = "image"` and `origin = "emoticon"`
- **AND** the system opener is not called by neoment

### Requirement: Custom reactions open through the configured handler
When the user opens a custom (`mxc://`) reaction image under the cursor, the client SHALL download the image and call the configured `room.on_open_attachment` handler instead of opening the file directly.

#### Scenario: Opening a custom reaction
- **GIVEN** a custom `room.on_open_attachment` handler is configured
- **AND** the cursor is on a custom reaction in a room buffer
- **WHEN** the user triggers the open attachment action
- **THEN** the handler is called once with the downloaded image's path
- **AND** the attachment argument has `type = "image"` and `origin = "reaction"`

### Requirement: Room avatars open through the configured handler
When the user opens the room avatar from the room info buffer, the client SHALL download the image and call the configured `room.on_open_attachment` handler instead of opening the file directly.

#### Scenario: Opening the room avatar
- **GIVEN** a custom `room.on_open_attachment` handler is configured
- **AND** the room has an avatar
- **WHEN** the user triggers the open avatar action in the room info buffer
- **THEN** the handler is called once with the downloaded image's path
- **AND** the attachment argument has `type = "image"` and `origin = "avatar"`

#### Scenario: Room without an avatar
- **GIVEN** the room has no avatar
- **WHEN** the user triggers the open avatar action
- **THEN** the handler is not called
- **AND** the user is told there is no avatar image to open

### Requirement: Attachment metadata never contains the access token
The attachment argument passed to `room.on_open_attachment` SHALL NOT contain the user's access token in any field.

#### Scenario: Image opened from an emoticon, reaction or avatar
- **WHEN** the handler is called for an emoticon, reaction or avatar image
- **THEN** the attachment's `url` is the homeserver media URL without an `access_token` query parameter
- **AND** the attachment's `mxc_url` is the original `mxc://` URI

### Requirement: Default handler behavior is preserved
With no custom handler configured, the client SHALL open emoticon, reaction and avatar images with the system opener, and SHALL keep its existing default behavior for message attachments.

#### Scenario: Default handler opens an emoticon
- **GIVEN** no custom `room.on_open_attachment` is configured
- **WHEN** the user opens a custom emoticon
- **THEN** the image is opened with the system opener, as before this change
