# Proposal

## Why

GitHub issue #36 asks for neoment to work on a bare Linux TTY: view images through the framebuffer and play audio through a terminal player. The `room.on_open_attachment` hook from #40 already lets users handle message attachments themselves. However, custom emoticons, custom (`mxc://`) reactions and room avatars still call `vim.ui.open` directly. On a TTY with no graphical session that call has nothing to hand the file to, so those images cannot be viewed, and no configuration can fix it.

## What Changes

- Opening a custom emoticon or a custom reaction image with `<localleader>o` in a room buffer calls `room.on_open_attachment` instead of `vim.ui.open`.
- Opening the room avatar with `<localleader>o` in the room info buffer calls `room.on_open_attachment` instead of `vim.ui.open`.
- For these images the hook receives an image attachment table built by neoment, with an `origin` field that tells it where the image came from. Message attachments also get an `origin` field, set to `"message"`.
- With the default handler, behavior is unchanged: these images still open with `vim.ui.open`.
- The README documents that the hook covers every open action. It also adds a TTY recipe that shows images with `chafa` and plays audio with `mpv` in a terminal split.

## Capabilities

### New Capabilities

- `attachment-opening`: How neoment opens message attachments, custom emoticons, custom reactions and room avatars, and how users can customize it through `room.on_open_attachment`.

### Modified Capabilities

None.

## Impact

- `lua/neoment/room.lua`: the emoticon and reaction branch of `M.open_attachment` calls the configured handler, and the message branch sets `origin`.
- `lua/neoment/room_info.lua`: `M.open_avatar` calls the configured handler.
- `lua/neoment/matrix/client.lua` / `lua/neoment/config.lua`: the type annotations for the hook's attachment argument gain the optional `origin` field.
- `README.md`: the hook documentation and a new TTY recipe.
- `tests/`: `tests/room_info_spec.lua` updates its `open_avatar` case, and a new spec covers the room's open paths.
- Users with a custom `on_open_attachment` now also receive emoticon, reaction and avatar images. A handler that only checks `attachment.type` keeps working, since these arrive as `type = "image"`. No new dependencies.
