# Tasks

## 1. Validated mxc parsing and token scope (util)

- [x] 1.1 Add `util.parse_mxc(uri)` per design D1 (anchored; server name with optional port or bracketed IPv6; media ID `[%w_%-]+`), with `---` docs. Verify with new `media_url_spec.lua` cases: valid URI, IPv6 with port, `https://…`, `https://x/mxc://a/b`, `mxc://a/../../b`, `mxc://a`, `mxc://a/b/c`, `nil`, all returning the expected values
- [x] 1.2 Change `util.mxc_to_url` to return `nil` when `parse_mxc` fails and update its `@return` to `string|nil`. Verify with spec cases: valid URI resolves to `<hs>/_matrix/client/v1/media/download/<server>/<id>`; each invalid input from 1.1 returns `nil`
- [x] 1.3 Add `util.is_media_url(url)` per D2 and switch `media_access_token` to use it. Verify with spec cases: `media_headers` returns the bearer header for a resolved mxc URL and for the same URL with `?access_token=old`; returns `nil` for `<hs>/_matrix/client/v3/account/whoami`, `<hs>/_matrix/client/v1/media/download/a/../x`, another host, and a `<hs>.evil.com` prefix

## 2. Attachments from events

- [x] 2.1 In `matrix/event.lua`, set `mxc_url`/`url` only for valid mxc `content.url`, and make `get_thumbnail` return `nil` for an invalid `thumbnail_url` (D3). Mark `url`/`mxc_url` optional in `matrix/client.lua` annotations. Verify with `media_url_spec.lua` "stored attachments" cases: `m.image` and `m.file` with `https://` `url` have `url == nil`; an `m.video` with a valid url and an `https://` `thumbnail_url` has a url and no thumbnail; no field of any of these attachments contains `access_token`; existing valid-mxc cases still pass

## 3. Inline rendering

- [x] 3.1 In `storage.fetch_image_source`, return `error.err(...)` for URLs where `util.is_media_url` is false instead of `error.ok(url)` (D4). Verify by updating the `fetch_image_source` cases in `media_url_spec.lua`: an `https://attacker.example/x.png?access_token=old` URL returns an error and starts no download; a cached homeserver URL with `?access_token=old` downloads the stripped URL with the current-token header
- [x] 3.2 In `room.lua` render, collect inline images only from `image` attachments and `video` thumbnails whose URL passes `util.is_media_url` (D4). Verify with a `room_spec.lua` test, stubbing `Snacks` and `storage.fetch_image_source`: rendering `m.image` (https url), `m.file`, `m.audio` and `m.location` messages calls `fetch_image_source` zero times, while a valid-mxc `m.image` calls it once with the homeserver URL

## 4. Open and save

- [x] 4.1 In `room.open_attachment`, notify "This attachment has no downloadable media" and return without calling `fetch_to_temp` or the handler when a non-location attachment has no homeserver media `url` per `util.is_media_url` (D5). Verify with `room_open_attachment_spec.lua` cases for an `m.image` with an `https://` source and for a cached `https://attacker.example/x.png?access_token=old` URL: `fetch_to_temp` and the handler are not called, and the notification is emitted
- [x] 4.2 Apply the same guard in `room.save_attachment`, before the save-path prompt. Verify with a `room_save_attachment_spec.lua` case: `vim.ui.input` and `fetch_to_temp` are not called for an attachment with no `url` nor for a cached non-homeserver URL
- [x] 4.3 In `room.forward_message`, include the attachment only when `util.parse_mxc(attachment.mxc_url)` succeeds, otherwise forward the body only (D5). Verify with `room_forward_message_spec.lua`: a valid-mxc attachment is forwarded with its mxc URL; an attachment without one sends no `attachment` param

## 5. Emoticons, reactions and avatars

- [x] 5.1 Replace the `match("^mxc://")` gates for emoticon and reaction extmarks in `room.lua`, and make the hover previews and the mxc branch of `open_attachment` bail when `mxc_to_url` returns `nil` (D6). Verify with a `room_open_attachment_spec.lua` case: an emoticon extmark with `mxc://example.org/../../v3/account/whoami` triggers no `fetch_to_temp`; existing valid emoticon and reaction cases still pass
- [x] 5.2 Replace the `^mxc://` gates in `room_info.lua` (avatar render and open) with `util.parse_mxc`. Verify with `room_info_spec.lua`: the existing "does not fetch an avatar whose URL is not mxc://" case passes, plus a new case for a malformed `mxc://` avatar that is neither fetched nor opened. Update the `mxc_to_url` stub in that spec to return `nil` for invalid input

## 6. Integration check

- [x] 6.1 Run `devbox run test` and confirm the full suite passes; `grep -rn 'match("^mxc://")' lua/` returns no results and every `mxc_to_url` call site handles a `nil` result
