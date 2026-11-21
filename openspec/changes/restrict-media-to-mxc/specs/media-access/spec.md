# Spec Delta

## Purpose

Defines how the client turns Matrix content URIs into downloadable media, which media it fetches automatically or on request, and the only places the user's access token may be sent when downloading media.

## ADDED Requirements

### Requirement: Only well-formed mxc URIs resolve to media
The client SHALL resolve a content URI to a download URL only when the whole URI has the form `mxc://<server-name>/<media-id>`. Here `<server-name>` is a valid Matrix server name and `<media-id>` contains only letters, digits, `_` and `-`. The download URL SHALL be on the user's homeserver media download endpoint. Any other value SHALL resolve to no URL.

#### Scenario: Valid mxc URI
- **WHEN** the client resolves `mxc://example.org/AbC_123-x` with homeserver `https://hs.example`
- **THEN** the result is `https://hs.example/_matrix/client/v1/media/download/example.org/AbC_123-x`

#### Scenario: HTTPS URL
- **WHEN** the client resolves `https://attacker.example/x.png`
- **THEN** the result is no URL

#### Scenario: mxc appears later in the string
- **WHEN** the client resolves `https://attacker.example/mxc://example.org/abc`
- **THEN** the result is no URL

#### Scenario: Path traversal in the media ID
- **WHEN** the client resolves `mxc://example.org/../../v3/account/whoami`
- **THEN** the result is no URL

#### Scenario: Missing or extra path segments
- **WHEN** the client resolves `mxc://example.org` or `mxc://example.org/abc/def`
- **THEN** the result is no URL

### Requirement: Access token is only sent for resolved mxc media
The client SHALL send the user's access token with a media download only when the URL was produced by resolving a valid `mxc://` URI to the homeserver's media download endpoint. It SHALL NOT send the token in a URL query string, to any other host, or to any other homeserver path.

#### Scenario: Download of resolved mxc media
- **WHEN** the client downloads media resolved from `mxc://example.org/abc`
- **THEN** the request carries the current access token in an `Authorization: Bearer` header
- **AND** the URL contains no `access_token` parameter

#### Scenario: Other URL on the homeserver
- **WHEN** the client is asked to download `https://hs.example/_matrix/client/v3/account/whoami`
- **THEN** the request carries no access token

#### Scenario: URL on another host
- **WHEN** the client is asked to download `https://attacker.example/x.png`
- **THEN** the request carries no access token

### Requirement: Attachments without a valid mxc source have no downloadable media
For `m.image`, `m.file`, `m.audio`, `m.video` and `m.sticker` messages, the client SHALL treat the attachment as having no downloadable media when `content.url` is not a valid `mxc://` URI. It SHALL treat a thumbnail as absent when `content.info.thumbnail_url` is not a valid `mxc://` URI. The message SHALL still be displayed with its body text.

#### Scenario: Image with an HTTPS url
- **WHEN** the client receives an `m.image` event whose `content.url` is `https://attacker.example/x.png`
- **THEN** the message is displayed with its body
- **AND** no URL derived from the event contains `access_token`
- **AND** the attachment has no downloadable URL

#### Scenario: File with an HTTPS url
- **WHEN** the client receives an `m.file` event whose `content.url` is `https://attacker.example/f.pdf`
- **THEN** the attachment has no downloadable URL

#### Scenario: Video with an HTTPS thumbnail
- **WHEN** the client receives an `m.video` event with a valid `mxc://` `content.url` and `content.info.thumbnail_url` set to `https://attacker.example/t.png`
- **THEN** the video attachment has a downloadable URL
- **AND** it has no thumbnail

### Requirement: Inline images only for homeserver media
When inline images are enabled, the client SHALL draw a message image inline only for image attachments (including stickers) and video thumbnails whose media resolves to the user's homeserver. It SHALL NOT draw, or request, any other attachment or URL inline.

#### Scenario: Image from a valid mxc URI
- **GIVEN** inline images are available
- **WHEN** a room buffer renders an `m.image` message with a valid `mxc://` URL
- **THEN** the image is downloaded from the homeserver and drawn inline

#### Scenario: Image with a non-mxc URL is not fetched on render
- **GIVEN** inline images are available
- **WHEN** a room buffer renders an `m.image` message whose `content.url` is `https://attacker.example/x.png`
- **THEN** no request is made to `attacker.example`
- **AND** no image is drawn for that message

#### Scenario: Non-image attachments are not drawn inline
- **GIVEN** inline images are available
- **WHEN** a room buffer renders an `m.file`, `m.audio` or `m.location` message
- **THEN** no image is drawn inline for that message

### Requirement: Opening or saving an attachment without media is refused
When the user opens or saves the attachment of a message that has no downloadable media, the client SHALL NOT make any network request. It SHALL tell the user that the attachment has no downloadable media. Location attachments keep their existing map-link behavior.

#### Scenario: Opening an image with a non-mxc URL
- **WHEN** the user opens the attachment of an `m.image` message whose `content.url` is `https://attacker.example/x.png`
- **THEN** no download is started
- **AND** the user is notified that the attachment has no downloadable media
- **AND** the open-attachment handler is not called

#### Scenario: Saving a file with a non-mxc URL
- **WHEN** the user saves the attachment of an `m.file` message whose `content.url` is `https://attacker.example/f.pdf`
- **THEN** no download is started and the user is notified

### Requirement: Emoticons, reactions and avatars use the same media rules
Custom emoticons, custom reactions and room avatars SHALL be previewed, drawn and opened only when their source is a valid `mxc://` URI. They SHALL follow the same access-token rule as message attachments.

#### Scenario: Malformed mxc emoticon
- **WHEN** a message contains an emoticon link to `mxc://example.org/../../v3/account/whoami`
- **THEN** the emoticon is not previewed or opened
- **AND** no request is sent to the homeserver for it

#### Scenario: Room avatar with a valid mxc URI
- **WHEN** the room info buffer shows a room whose avatar is `mxc://example.org/abc123`
- **THEN** the avatar is downloaded from the homeserver with the access token in a header

### Requirement: Cached media URLs are not fetched as stored
The client SHALL NOT fetch a media URL restored from a session saved by an earlier version unless that URL is homeserver media. Any `access_token` query parameter it carries SHALL be removed before use. A cached URL on another host SHALL NOT be fetched, automatically or on request.

#### Scenario: Cached last message points to another host with a token
- **GIVEN** a restored session whose cached last message has an image URL `https://attacker.example/x.png?access_token=old`
- **WHEN** the room buffer renders that message
- **THEN** no request is made to `attacker.example`

#### Scenario: Cached homeserver media URL with an old token
- **GIVEN** a restored session whose cached image URL is homeserver media with `?access_token=old`
- **WHEN** the image is fetched
- **THEN** the request URL has no `access_token` parameter and the current token is sent in a header
