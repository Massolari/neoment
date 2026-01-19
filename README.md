# Neoment

A Matrix client for Neovim, bringing chat functionality directly into your editor.

> **⚠️ Warning:** This plugin is currently in beta and under active development. The API may change without prior notice. Use at your own risk and expect breaking changes between updates.

[![#neoment-nvim:matrix.org](https://img.shields.io/badge/matrix-%23neoment--nvim:matrix.org-blue?logo=matrix)](https://matrix.to/#/#neoment-nvim:matrix.org)
[![License](https://img.shields.io/github/license/Massolari/neoment)](LICENSE)

## Description

Neoment is a Matrix protocol client implementation for Neovim that allows you to chat, and stay connected without leaving your editor.

**Note:** Neoment does not currently support End-to-End Encryption (E2EE). Encrypted rooms will not be accessible.

**Features:**

- List rooms
- Join rooms
- Leave rooms
- View spaces
- Rich-replies
- Edit messages
- Forward messages
- Image display (if you have [Snacks](https://github.com/folke/snacks.nvim))
- Download/open media
- Upload file
- Upload image from clipboard
- Reactions
- Threads
- Mark room as read/unread/favorite/low priority
- Compose messages with markdown support
- Desktop notifications for new messages

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
	"Massolari/neoment",
	dependencies = {
		"nvim-lua/plenary.nvim",
	}
}
```

### Using vim.pack (Neovim 0.12+)

```lua
-- In your init.lua:
vim.pack.add({
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/Massolari/neoment" ,
})
```

## Companion Plugins

For the best experience, it is recommended to install the following companion plugins:

- [which-key](https://github.com/folke/which-key.nvim): As most of keybindings are under the `<localleader>` key, which-key helps to discover them easily. When pressing `<localleader>`, which-key will show you the available keybindings for the current buffer.
- [snacks.nvim](https://github.com/folke/snacks.nvim): For displaying images directly in Neovim buffers.
- Completion engine to easily type emojis in the compose buffer, such as:
    - [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) with [cmp-emoji](https://github.com/hrsh7th/cmp-emoji/)
    - [blink.cmp](https://github.com/Saghen/blink.cmp) with [blink-emoji.nvim](https://github.com/moyiz/blink-emoji.nvim)
- Picker plugin to enhance the room selection experience through `vim.ui.select`, such as:
    - [snacks.nvim](https://github.com/folke/snacks.nvim)
    - [fzf-lua](https://github.com/ibhagwan/fzf-lua/)
    - [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) with [telescope-ui-select.nvim](https://github.com/nvim-telescope/telescope-ui-select.nvim)

## Usage

### First Time Setup

1. Open Neovim and run `:Neoment` to authenticate with your Matrix homeserver
1. Provide your username and password
1. The plugin will automatically sync and display your rooms

### Commands

- `:Neoment` - Login to your Matrix account. If already logged in, opens the rooms list
- `:Neoment join <room_id_or_alias>` - Join a room by its ID or alias
- `:Neoment logout` - Logout and clear session data
- `:Neoment open_rooms` - Use `vim.ui.select` to select a already opened room/space
- `:Neoment reload_config` - Reload the configuration. You can modify settings in the `vim.g.neoment` table at any time and apply the changes instantly by running this command.
- `:Neoment rooms` - Use `vim.ui.select` to select and open a room/space
- `:Neoment sync_start` - Start syncing messages
- `:Neoment sync_stop` - Stop syncing messages

### Configuration

Neoment uses the global variable `vim.g.neoment` for configuration. You can set it in your Neovim configuration file (`init.lua` or equivalent).

```lua
vim.g.neoment = {
	-- Save session data to disk (default: true)
	save_session = true,
	
	-- Custom notifier function (optional)
	-- By default, uses vim.notify
	notifier = function(msg, level, opts)
		vim.notify(msg, level, opts)
	end,
	
	-- Desktop notifications can be configured per room type.
	-- The buffer setting applies to currently open rooms (excluding the focused room),
	-- while favorites, people, and rooms settings apply to all rooms of those types.
	desktop_notifications = {
		enabled = true,  -- Enable or disable desktop notifications (default: true)
		
		-- Custom desktop notifier handler (optional)
		-- By default, uses vim.fn.system to call:
		-- - gdbus on Linux
		-- - osascript on macOS
		-- - PowerShell on Windows
		handler = function(title, content)
			if jit.os == "Linux" or jit.os == "BSD" then
				-- Using gdbus for Linux/BSD
			elseif jit.os == "Windows" then
				-- Using powershell for Windows
			elseif jit.os == "OSX" then
				-- Using osascript for macOS
			end
		end,
		
		-- Notification levels for different room types
		-- Options: "all", "mentions", "none"
		-- "all" - notify for all new messages
		-- "mentions" - notify only for mentions/highlights
		-- "none" - do not notify
		buffer = "all", -- When buffer is set to "none", it'll inherit the room setting from its type
		favorites = "all",
		people = "all",
		rooms = "mentions"
	},
	
	-- Picker configuration (optional)
	-- Customize the UI for room selection (default: vim.ui.select)
	picker = {
		-- Custom picker for `:Neoment rooms` command and other room selections
		-- Receives items (list of {room, line}), a callback function and options
		-- room is the room object, line is the formatted string to display
		-- The callback must be called with the selected room in order to open it
		-- options is a table with one `prompt` field containing the prompt string
		rooms = function(items, callback, options)
			vim.ui.select(items, {
				prompt = options.prompt,
				format_item = function(item) return item.line end,
			}, function(choice)
				if choice then callback(choice.room) end
			end)
		end,
		
		-- Custom picker for `:Neoment open_rooms` command
		-- Same signature as rooms picker
		open_rooms = function(items, callback, options)
			vim.ui.select(items, {
				prompt = options.prompt,
				format_item = function(item) return item.line end,
			}, function(choice)
				if choice then callback(choice.room) end
			end)
		end,
	},
	
	-- Settings for the room list
	rooms = {
		-- How to display the last message. The last message is shown below the room name
		-- Options:
		-- "no" - do not show the last message
		-- "message" - show the last message content
		-- "sender_message" - show the sender and last message content, each one on its own line
		-- "sender_message_inline" - show the sender and last message content on the same line.
		display_last_message = "message",
	}
	
	-- Icon configuration (all optional)
	icon = {
		invite = "",              -- Icon for room invites
		buffer = "󰮫",              -- Icon for buffer rooms
		favorite = "",            -- Icon for favorite rooms
		people = "",              -- Icon for people/DMs
		space = "󰴖",               -- Icon for spaces
		room = "󰮧",                -- Icon for regular rooms
		low_priority = "󰘄",       -- Icon for low priority rooms
		reply = "↳",               -- Icon for message replies
		right_arrow = "▶",         -- Icon for collapsed sections
		down_arrow = "▼",          -- Icon for expanded sections
		down_arrow_circle = "",  -- Icon for down arrow in circle
		bell = "󰵛",                -- Icon for mentions/highlights
		dot = "•",                 -- Icon for unread indicator
		dot_circle = "",          -- Icon for dot in circle
		vertical_bar = "│",        -- Icon for vertical separator
		vertical_bar_thick = "┃",  -- Icon for thick vertical separator
		tree_branch = "├",         -- Icon for tree branch
		image = "󰋩",               -- Icon for images
		file = "󰈙",                -- Icon for files
		audio = "",               -- Icon for audio files
		location = "󰍎",            -- Icon for location
		video = "",               -- Icon for video files
	},
}
```

### Key Bindings

Neoment uses `<Plug>` mappings for all its keybindings. There is no `vim.g` configuration option for keybindings; users should define their own mappings in their Neovim configuration files.

If you wish, you can create files in the `ftplugin` directory of your Neovim configuration to set up buffer-local mappings.

For example, to change the key for opening rooms in the Rooms Buffer from `<CR>` to `<BS>`, create a file at `~/.config/nvim/ftplugin/neoment_rooms.lua` with the following content:

```lua
vim.keymap.set("n", "<BS>", "<Plug>NeomentRoomsEnter", { buffer = 0 })
```

Below are the default keybindings for each buffer type.

#### Rooms Buffer

Filetype: `neoment_rooms`

| Description                           | Mapping                               | Default          |
| --------------------------------------| ------------------------------------- | ---------------- |
| Open room/space under cursor          | `<Plug>NeomentRoomsEnter`             | `<CR>`           |
| Toggle fold under cursor              | `<Plug>NeomentRoomsToggleFold`        | `<Tab>`          |
| Close window                          | `<Plug>NeomentRoomsClose`             | `q`              |
| Toggle favorite                       | `<Plug>NeomentRoomsToggleFavorite`    | `<localleader>a` |
| Toggle direct messaging room          | `<Plug>NeomentRoomsToggleDirect`      | `<localleader>d` |
| Find room (open `vim.ui.select`)      | `<Plug>NeomentRoomsPick`              | `<localleader>f` |
| Find open room (open `vim.ui.select`) | `<Plug>NeomentRoomsPickOpen`          | `<localleader>F` |
| Show room information                 | `<Plug>NeomentRoomsShowRoomInfo`      | `<localleader>i` |
| Toggle low priority                   | `<Plug>NeomentRoomsToggleLowPriority` | `<localleader>l` |
| Toggle read/unread                    | `<Plug>NeomentRoomsToggleRead`        | `<localleader>r` |

#### Room Buffer

Filetype: `neoment_room`

| Description                            | Mapping                                 | Default          |
| -------------------------------------- | --------------------------------------- | ---------------- |
| Compose/send message                   | `<Plug>NeomentRoomCompose`              | `<CR>`           |
| React to message                       | `<Plug>NeomentRoomReact`                | `<localleader>a` |
| Redact (delete) message                | `<Plug>NeomentRoomRedact`               | `<localleader>d` |
| Edit message                           | `<Plug>NeomentRoomEdit`                 | `<localleader>e` |
| Find room (open `vim.ui.select`)       | `<Plug>NeomentRoomFind`                 | `<localleader>f` |
| Find open room (open `vim.ui.select`)  | `<Plug>NeomentRoomFindOpen`             | `<localleader>F` |
| Show current room information          | `<Plug>NeomentRoomShowRoomInfo`         | `<localleader>i` |
| Toggle room list                       | `<Plug>NeomentRoomToggleRoomList`       | `<localleader>l` |
| Leave room                             | `<Plug>NeomentRoomLeave`                | `<localleader>L` |
| Set read marker                        | `<Plug>NeomentRoomSetReadMarker`        | `<localleader>m` |
| Open attachment                        | `<Plug>NeomentRoomOpenAttachment`       | `<localleader>o` |
| Load previous messages                 | `<Plug>NeomentRoomLoadPrevious`         | `<localleader>p` |
| Quit room (close the buffer)           | `<Plug>NeomentRoomQuit`                 | `<localleader>q` |
| Reply to message                       | `<Plug>NeomentRoomReply`                | `<localleader>r` |
| Go to replied message                  | `<Plug>NeomentRoomGoToReplied`          | `<localleader>R` |
| Open thread                            | `<Plug>NeomentRoomOpenThread`           | `<localleader>t` |
| Save attachment                        | `<Plug>NeomentRoomSaveAttachment`       | `<localleader>s` |
| Upload attachment                      | `<Plug>NeomentRoomUploadAttachment`     | `<localleader>u` |
| Upload image from clipboard            | `<Plug>NeomentRoomUploadClipboardImage` | `<localleader>U` |
| Forward message                        | `<Plug>NeomentRoomForwardMessage`       | `<localleader>w` |
| Toggle zoom of image under cursor      | `<Plug>NeomentRoomToggleZoomImage`      | `<localleader>z` |

#### Compose Buffer

Filetype: `neoment_compose`

| Description            | Mapping                           | Default |
| ---------------------- | --------------------------------- | ------- |
| Send message           | `<Plug>NeomentComposeSend`        | `<CR>`  |
| Send message (insert)  | `<Plug>NeomentComposeSendInsert`  | `<C-s>` |
| Abort compose          | `<Plug>NeomentComposeAbort`       | `<Esc>` |
| Abort compose (insert) | `<Plug>NeomentComposeAbortInsert` | `<C-c>` |

You can type `<C-x><C-o>` in insert mode, after typing `@`, to trigger the completion menu for mentions.

#### Space Buffer

Filetype: `neoment_space`

| Description                      | Mapping                            | Default          |
| -------------------------------- | ---------------------------------- | ---------------- |
| Open room/space under cursor     | `<Plug>NeomentSpaceEnter`          | `<CR>`           |
| Find room (open `vim.ui.select`) | `<Plug>NeomentSpaceFind`           | `<localleader>f` |
| Quit window (close the buffer)   | `<Plug>NeomentSpaceQuit`           | `<localleader>q` |
| Toggle room list                 | `<Plug>NeomentSpaceToggleRoomList` | `<localleader>l` |

#### Room Info Buffer

Filetype: `neoment_info_room`

| Description                           | Mapping                           | Default          |
| ------------------------------------- | --------------------------------- | ---------------- |
| Find room (open `vim.ui.select`)      | `<Plug>NeomentInfoRoomFind`       | `<localleader>f` |
| Find open room (open `vim.ui.select`) | `<Plug>NeomentInfoRoomFindOpen`   | `<localleader>F` |
| Toggle room list                      | `<Plug>NeomentInfoRoomToggleList` | `<localleader>l` |

## Inspiration

Neoment draws inspiration from some excellent Matrix clients:

- **[iamb](https://github.com/ulyssa/iamb)**
- **[gomuks](https://github.com/tulir/gomuks)**
- **[ement.el](https://github.com/alphapapa/ement.el)**

## Contributing

Contributions are welcome! Please note that as this project is in beta, architectural changes may occur. Feel free to:

- Report bugs and issues
- Suggest features and improvements
- Submit pull requests

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or discussions, please use the GitHub issue tracker.
