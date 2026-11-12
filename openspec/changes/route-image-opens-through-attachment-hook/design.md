# Design

## Context

There are three places that open a downloaded file, and only one of them goes through the hook:

```
room.lua    M.open_attachment
              +-- emoticon / mxc reaction --> vim.ui.open(path)              (bypass)
              +-- message attachment -------> config.room.on_open_attachment
room_info.lua M.open_avatar ----------------> vim.ui.open(path)              (bypass)
```

The hook is typed as `fun(path, attachment: neoment.matrix.client.MessageAttachment)` (`config.lua`). For emoticons and reactions, the only data available is the extmark data (`emoticon_url` / `reaction_mxc_url`, plus `emoticon_title` / `reaction_label`). For avatars, the only data is `room.avatar_url`. None of them have a MIME type, and both paths already force a `.png` filename. Real attachments store `url = util.mxc_to_url(homeserver, mxc)` without the token. The token is appended only for the download.

## Goals / Non-Goals

**Goals:**
- Every open action goes through `config.get().room.on_open_attachment`.
- Hook authors can tell images that came from messages apart from emoticons, reactions and avatars.

**Non-Goals:**
- A TTY-aware default handler (option C from the exploration). The README recipe covers TTY setups instead.
- Rendering images inline in the buffer when Snacks can't draw them (option D).
- Changing the CursorHold float preview, which renders with Snacks and doesn't open files.

## Decisions

**1. Build a synthetic `MessageImage` rather than add a second hook.**
The emoticon, reaction and avatar paths pass a table shaped like a `MessageImage`: `type = "image"`, `filename`, `mxc_url`, `url` (no token), and `mimetype = "image/png"`. That way existing handlers that branch on `attachment.type` handle these images with no changes. A separate `on_open_image` hook was rejected because users on a TTY would have to configure two hooks for one job, and #40 made a single hook the public API.

**2. Add an optional `origin` field: `"message" | "emoticon" | "reaction" | "avatar"`.**
Without it, a handler can't tell a forced-`.png` emoticon from a real photo. The field goes in the hook's type: we either add `origin?` to `BaseAttachment` and `MessageLocation`, or change the hook alias to `MessageAttachment & { origin?: ... }`. The implementer can pick whichever LuaLS accepts cleanly. It is optional, so code that builds attachments elsewhere doesn't break. The message branch sets it on a shallow copy (`vim.tbl_extend("force", message.attachment, { origin = "message" })`), so the stored message isn't changed.

**3. `mimetype = "image/png"` is a best guess.**
It matches the `.png` filename these paths already use. Viewers like `chafa`, `mpv` and `xdg-open` detect the real format from the file contents. The alternatives were leaving `mimetype` nil, which breaks the `string` type and any `mimetype:match(...)` in user handlers, or adding a HEAD request to find the real type, which adds latency for little benefit.

**4. Avatar uses the same handler, read from `config` at call time.**
`room_info.lua` already requires `neoment.config`. Reading the handler when the call happens, not at module load, matches `room.lua` and keeps tests that stub `config.get` working.

**5. A small local helper per module, not a shared util.**
The synthetic attachment is about five lines. Each module (`room.lua`, `room_info.lua`) builds it inline or in a local function. If a third caller appears, it can move to `util`.

## Risks / Trade-offs

- [Users with a custom handler that only ever expected message attachments now receive emoticons and avatars] → These arrive as `type = "image"` with a valid local path, so `vim.ui.open(path)` fallbacks keep working. The README calls out `origin`.
- [`mimetype` may not match the actual file (for example, an animated GIF emoticon)] → Documented in the hook's README comment, and `origin` lets handlers treat these images separately.
- [The `room_info_spec` avatar test stubs `vim.ui.open`, so it breaks once the code calls the hook] → The test changes to stub `room.on_open_attachment` in its `config` mock. This is part of the tasks.

## Migration Plan

No migration. The default handler still calls `vim.ui.open` for images, so users who haven't configured anything see no change. To roll back, revert the commit.
