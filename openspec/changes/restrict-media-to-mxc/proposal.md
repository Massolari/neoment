# Proposal

## Why

Issue #50 reports that message attachments whose `url` or `thumbnail_url` is not `mxc://` get the user's access token appended. Since #52 the token goes in an `Authorization` header and only to URLs under the homeserver, so that exact leak is closed. Media handling still trusts URLs taken from event content, though:

- A non-`mxc://` attachment URL is kept as the attachment's fetchable URL. With Snacks installed it is downloaded as soon as the message renders, with no click. Anyone who can post in a room learns the user's IP address and when they read the message.
- The image viewer receives non-homeserver URLs exactly as stored. A session cache written before #52 can still hold `https://attacker…?access_token=<token>` in a room's last message, and access tokens issued without refresh never expire.
- `mxc_to_url` only checks that the string contains `mxc://` somewhere, and never checks the server name or media ID. A crafted URI such as `mxc://hs/../../v3/account/whoami` resolves to a non-media homeserver endpoint, which then gets the `Authorization` header.
- Inline rendering picks up every attachment type, not just images and thumbnails. That includes location attachments, whose URL is a Google Maps page.

## What Changes

- Media is only fetchable when it comes from a well-formed `mxc://<server-name>/<media-id>` URI. Anything else resolves to no URL.
- Message attachments and thumbnails with a non-`mxc://` (or malformed) URL have no fetchable URL. They are rendered as text only, are never drawn inline, and opening or saving them tells the user there is no downloadable media. **BREAKING** for any room that relied on plain `https://` media URLs. The Matrix spec requires `mxc://`, so conforming clients do not send them.
- The access token is only attached to URLs built from a valid `mxc://` URI, never to arbitrary URLs on the homeserver.
- Inline images are only drawn for image attachments and for video thumbnails, and only when the media resolves to the user's homeserver. Nothing else is ever handed to the image viewer.
- Emoticon and reaction previews, emoticon and reaction opens, and room avatar render and open all go through the same validated resolution.
- Media URLs stored in the session cache by earlier versions are never fetched as-is, automatically or when opening or saving. Only media that re-resolves from its `mxc://` source is fetched.
- Forwarding a message only carries its attachment when it has a valid `mxc://` source; otherwise only the body is forwarded.

## Capabilities

### New Capabilities
- `media-access`: How the client turns Matrix content URIs into downloadable media, which media it fetches automatically or on request, and where the access token may be sent.

### Modified Capabilities
<!-- None: no existing spec covers media. The in-flight `route-image-opens-through-attachment-hook` change (attachment-opening) defines which handler opens media. It is unaffected, except that media with no valid source is never downloaded. -->

## Impact

- `lua/neoment/util.lua`: `mxc_to_url` gains anchored, validated parsing; the media-token check becomes mxc-based.
- `lua/neoment/matrix/event.lua`: `get_attachment` / `get_thumbnail` produce no `url` for invalid sources.
- `lua/neoment/storage.lua`: `fetch_image_source` stops handing non-homeserver URLs to the viewer.
- `lua/neoment/room.lua`: inline image collection, hover previews, `open_attachment`, `save_attachment`, `forward_message`.
- `lua/neoment/room_info.lua`: avatar render and open use the shared resolver.
- `lua/neoment/matrix/client.lua`: attachment `url` becomes optional in type annotations.
- Tests: `tests/media_url_spec.lua`, `tests/room_open_attachment_spec.lua`, `tests/room_save_attachment_spec.lua`, `tests/room_forward_message_spec.lua`, `tests/room_info_spec.lua`, `tests/room_spec.lua`.
- No new dependencies. No change to the session file format.
