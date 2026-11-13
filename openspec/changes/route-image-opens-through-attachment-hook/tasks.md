# Tasks

## 1. Hook type

- [x] 1.1 Add the optional `origin` field (`"message"|"emoticon"|"reaction"|"avatar"`) with `--- @field` annotations, either on `BaseAttachment` and `MessageLocation` in `lua/neoment/matrix/client.lua` or on the `RoomOpenAttachmentHandler` alias in `lua/neoment/config.lua` (design decision 2). Verify that `devbox run test` still passes and that LuaLS reports no new diagnostics in either file.

## 2. Room buffer opens

- [x] 2.1 Create `tests/room_open_attachment_spec.lua`, using the module reset pattern from `tests/matrix_room_avatar_spec.lua`. Stub `neoment.storage.fetch_to_temp` to call its callback synchronously, stub `neoment.config.get` to return a spy `room.on_open_attachment`, spy on `vim.ui.open`, and flush `vim.schedule` with `vim.wait`. Add failing cases for an emoticon and a reaction under the cursor (seed the extmark and buffer data the way `room.lua` reads it). Each case asserts that the handler gets `type = "image"`, the matching `origin`, a `url` with no `access_token`, and the `mxc_url`, and that `vim.ui.open` is not called. Verify with `devbox run test` that the cases fail.
- [x] 2.2 In `M.open_attachment` in `lua/neoment/room.lua`, replace `vim.ui.open(path)` in the emoticon/reaction branch with a call to `config.get().room.on_open_attachment(path, attachment)`. `attachment` is a synthetic image built per design decisions 1–3, with `origin` set to `"emoticon"` when `emoticon_url` is set and `"reaction"` otherwise. Verify that the 2.1 cases pass.
- [x] 2.3 In the message branch, pass `vim.tbl_extend("force", message.attachment, { origin = "message" })` to the handler. Add a test that an audio message attachment reaches the handler with `origin = "message"` and that `message.attachment` itself is not modified. Verify with `devbox run test`.

## 3. Room info avatar

- [x] 3.1 Update the "fetches avatar and opens it" case in `tests/room_info_spec.lua` so the `neoment.config` mock returns a spy `room.on_open_attachment`. Assert that the spy gets `/tmp/Test_Room.png` and an attachment with `type = "image"`, `origin = "avatar"`, `mxc_url = "mxc://example.org/abc123"` and a `url` with no `access_token`, and that `vim.ui.open` is not called. Verify that the test fails before 3.2.
- [x] 3.2 In `M.open_avatar` in `lua/neoment/room_info.lua`, replace `vim.ui.open(path)` with the configured handler and a synthetic avatar attachment. Verify that 3.1 and the existing "no avatar" case pass with `devbox run test`.

## 4. Documentation

- [x] 4.1 Update the `room.on_open_attachment` comment in `README.md`. It should say that the hook also receives custom emoticons, custom reactions and room avatars, describe the `origin` field, and say that `mimetype` is `image/png` as a best guess for those. Update the "open the emoticon/reaction image externally" sentences and the room info "Open avatar in external viewer" row so they say the configured handler is used. Verify by reading the rendered README.
- [x] 4.2 Add a "Using neoment on a TTY" subsection to `README.md` with a working `on_open_attachment` example. It should open images with `chafa` and audio/video with `mpv` in a terminal split (the same split pattern as the default in `lua/neoment/config.lua`), fall back to `vim.ui.open` otherwise, and note that inline images need a terminal Snacks supports. Verify that the snippet loads without errors by pasting it into `vim.g.neoment` in a scratch Neovim session.

## 5. Manual check

- [ ] 5.1 In Neovim, configure the 4.2 handler and open a custom emoticon, a custom reaction, a room avatar and an audio message. Verify that each one reaches the handler (chafa or mpv split), and that with the default config the emoticon still opens in the OS viewer.

## Workflow follow-up

- Reference GitHub issue #36 in the PR and ask the reporter whether chafa-quality output meets their framebuffer use case.
- Archive the change after review.
