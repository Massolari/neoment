# Design

## Context

See proposal.md (Why). State of `master` relevant to the approach:

- `util.mxc_to_url(homeserver, mxc_uri)` returns its input unchanged unless it contains `mxc://` anywhere (`find`, unanchored). It then strips the first 6 characters and appends the rest to `<homeserver>/_matrix/client/v1/media/download/` with no validation.
- `util.media_headers(url)` returns `Authorization: Bearer <token>` for any URL starting with `<homeserver>/`. It is the single place the media token is attached, and it is used by `open_attachment`, `save_attachment`, `room_info` avatar open and `storage.fetch_image_source`.
- `storage.fetch_image_source(url, cb)` downloads homeserver media to a private cache. For any other URL it calls `cb(error.ok(url))` with the **original** URL, which may still carry a legacy `?access_token=`, and the image viewer (Snacks) then fetches it itself.
- `event.lua` `get_attachment` sets `mxc_url = content.url` and `url = mxc_to_url(...)`. `get_thumbnail` does the same for `thumbnail_url`.
- `room.lua` render collects `message.attachment.thumbnail or message.attachment` for **every** attachment type into `images` and passes `image.url` to `fetch_image_source`.
- Emoticon and reaction extmarks and `room_info` avatars already gate on `^mxc://` (#49), but then call the unvalidated `mxc_to_url`.
- The session cache keeps each room's last message, including its `attachment.url`, so URLs computed by older versions get restored.

## Goals / Non-Goals

**Goals:**
- One validated parser that every media path goes through. No call site does its own `^mxc://` check any more.
- Media-token scope narrowed from "anything on the homeserver" to "the media download endpoint for a valid server/media-id pair".
- Inline rendering can never cause a request to a host other than the homeserver.

**Non-Goals:**
- Supporting plain `https://` media from non-conforming senders, for example by showing them as tokenless links. Can be revisited later as an explicit opt-in.
- Thumbnail endpoint support (`/media/thumbnail`). Downloads stay on `/media/download`.
- Encrypted attachments (`content.file`). Unchanged and out of scope.
- Rewriting the session cache on disk. Stale URLs are neutralized when read, not migrated.

## Decisions

### D1. `util.parse_mxc(uri)` plus a stricter `util.mxc_to_url`
Add `util.parse_mxc(uri) -> server_name|nil, media_id|nil`, anchored on the whole string:
- server name: `[%w%.%-]+` optionally followed by `:%d+`, or a bracketed IPv6 literal `%[[%x:%.]+%]` optionally followed by `:%d+`;
- media ID: `[%w_%-]+` (the Matrix spec's allowed set);
- exactly one `/` between them and nothing after.

`mxc_to_url(homeserver, uri)` returns `nil` when `parse_mxc` fails, instead of echoing the input back. Return type becomes `string|nil`.

*Alternative considered:* the issue's `mxc_to_authenticated_url(homeserver, uri, token)`. Rejected because tokens moved to headers in #52, so a "URL with token" helper would bring back the query-string pattern. Changing `mxc_to_url` itself means no caller can still get a passthrough by accident.

### D2. `util.is_media_url(url)` decides token eligibility
`is_media_url(url)` is true only when `url` (with any `access_token` query parameter stripped) equals `<homeserver>/_matrix/client/v1/media/download/<server>/<media-id>`, where the tail passes the same server and media-ID patterns. `media_access_token` / `media_headers` use it instead of the `startswith(homeserver .. "/")` check. Legacy cached URLs built by `mxc_to_url` still qualify after stripping.

*Alternative considered:* tag attachments with a boolean such as `is_mxc` at parse time. Rejected because cached and in-memory URLs would need separate handling. A pure check on the URL covers both.

### D3. Attachments: `url` and `mxc_url` are `nil` for invalid sources
In `event.lua`, `mxc_url` is set only when `parse_mxc(content.url)` succeeds, and `url = mxc_to_url(...)` is then `nil` on its own. `get_thumbnail` returns `nil` unless `thumbnail_url` parses. Location attachments keep their Google Maps `url`, which is never token-eligible because of D2. Type annotations: `BaseAttachment.url` and `mxc_url` become optional.

### D4. Inline images: allowlist by type and by URL
In `room.lua` render, pick the image source as `attachment` when `type == "image"`, `attachment.thumbnail` when `type == "video"`, and nothing otherwise. Add it to `images` only if `util.is_media_url(source.url)`. In `storage.fetch_image_source`, a non-media URL returns `error.err("Not homeserver media")` instead of `error.ok(url)`. This second check catches every other caller (hover previews, room_info) and cached URLs.

### D5. Open and save refuse when there's nothing to fetch
`open_attachment` and `save_attachment` check `message.attachment.url` with `util.is_media_url` before calling `fetch_to_temp`. For non-location types whose `url` is not homeserver media (no `url`, or a URL cached by an earlier version that points elsewhere), they notify "This attachment has no downloadable media" and return. `save_attachment` checks before prompting for a path. The location branch stays as it is: its URL is built only from the numeric coordinates of `geo_uri`. `fetch_to_temp` sends no token for non-media URLs (D2).

`forward_message` includes the attachment only when its `mxc_url` passes `util.parse_mxc`. Otherwise only the body is forwarded, so no media event without a `url` (or with a cached non-mxc one) is sent.

### D6. Emoticons, reactions and avatars
Swap the inline `match("^mxc://")` gates in `room.lua` (emoticon extmarks, reaction extmarks) and `room_info.lua` (render and open) for `util.parse_mxc`. Hover previews and `open_attachment`'s mxc branch then call the now-nil-safe `mxc_to_url` and bail on `nil`.

## Risks / Trade-offs

- [Spec-conforming media IDs that use characters outside `[A-Za-z0-9_-]`, from older servers] → Synapse, Dendrite and Conduit all generate IDs in this set. If a real case turns up, widen the media-ID class while still excluding `/`, `.`, `?`, `#` and `%`.
- [Plain `https://` images from bridges or bots stop rendering] → Accepted. The Matrix spec requires `mxc://`, and the body text is still shown.
- [Hidden callers of `mxc_to_url` relying on passthrough] → grep shows only `event.lua`, `room.lua` (3) and `room_info.lua` (2). All are handled in the tasks, and the type change to `string|nil` surfaces any new ones via LuaLS.
- [IPv6/port server names mis-parsed] → covered by unit tests in `media_url_spec.lua`.

## Migration Plan

No data migration. Cached URLs are re-checked on every use (D2, D4). Rollback is reverting the commit; the cache format is unchanged.
