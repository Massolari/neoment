# Neoment

A Matrix client for Neovim, bringing chat functionality directly into your editor.

> **⚠️ Warning:** This plugin is currently in beta and under active development. The API may change without prior notice. Use at your own risk and expect breaking changes between updates.

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

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
	"Massolari/neoment",
	init = function()
		-- Optional: Configure settings
		vim.g.neoment = {
			save_session = true,
		}
	end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
	"Massolari/neoment",
	setup = function()
		vim.g.neoment = {
			save_session = true,
		}
	end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
" Optional configuration
let g:neoment = {'save_session': v:true}

Plug 'Massolari/neoment'
```

## Usage

### First Time Setup

1. Open Neovim and run `:Neoment` to authenticate with your Matrix homeserver
1. Provide your username and password
1. The plugin will automatically sync and display your rooms

### Commands

- `:Neoment` - Login to your Matrix account. If already logged in, opens the rooms list
- `:Neoment logout` - Logout and clear session data
- `:Neoment rooms` - Toggle the rooms list sidebar
- `:Neoment start sync` - Start syncing messages
- `:Neoment stop sync` - Stop syncing messages
- `:Neoment join <room_id_or_alias>` - Join a room by its ID or alias

### Configuration

```lua
vim.g.neoment = {
	-- Save session data to disk (default: true)
	save_session = true,
}
```

### Key Bindings

Neoment uses `<Plug>` mappings for all its keybindings. There is no `vim.g` configuration option for keybindings; users should define their own mappings in their Neovim configuration files.

Since keybindings are buffer-specific, you can create files in the `ftplugin` directory of your Neovim configuration to set up buffer-local mappings.

For example, to change the key for opening rooms in the Rooms Buffer from `<CR>` to `<BS>`, create a file at `~/.config/nvim/ftplugin/neoment_rooms.lua` with the following content:

```lua
vim.keymap.set("n", "<BS>", "<Plug>NeomentRoomsEnter", { buffer = 0 })
```

Below are the default keybindings for each buffer type.

#### Rooms Buffer

Filetype: `neoment_rooms`


| Description | Mapping | Default |
| --------------- | --------------- | --------------- |
| Open room/space under cursor | `<Plug>NeomentRoomsEnter` | `<CR>` |
| Toggle fold under cursor | `<Plug>NeomentRoomsToggleFold` | `<Tab>` |
| Close window | `<Plug>NeomentRoomsClose` | `q` |
| Toggle favorite | `<Plug>NeomentRoomsToggleFavorite` | `<localleader>a` |
| Find room (open picker) | `<Plug>NeomentRoomsPick` | `<localleader>f` |
| Toggle low priority | `<Plug>NeomentRoomsToggleLowPriority` | `<localleader>l` |
| Toggle read/unread | `<Plug>NeomentRoomsToggleRead` | `<localleader>r` |


#### Room Buffer

Filetype: `neoment_room`


| Description | Mapping | Default |
| --------------- | --------------- | --------------- |
| Compose/send message | `<Plug>NeomentRoomCompose` | `<CR>` |
| React to message | `<Plug>NeomentRoomReact` | `<localleader>a` |
| Redact (delete) message | `<Plug>NeomentRoomRedact` | `<localleader>d` |
| Edit message | `<Plug>NeomentRoomEdit` | `<localleader>e` |
| Find room (open picker) | `<Plug>NeomentRoomFind` | `<localleader>f` |
| Quit room (close the buffer) | `<Plug>NeomentRoomQuit` | `<localleader>q` |
| Toggle room list | `<Plug>NeomentRoomToggleRoomList` | `<localleader>l` |
| Leave room | `<Plug>NeomentRoomLeave` | `<localleader>L` |
| Set read marker | `<Plug>NeomentRoomSetReadMarker` | `<localleader>m` |
| Open attachment | `<Plug>NeomentRoomOpenAttachment` | `<localleader>o` |
| Load previous messages | `<Plug>NeomentRoomLoadPrevious` | `<localleader>p` |
| Reply to message | `<Plug>NeomentRoomReply` | `<localleader>r` |
| Go to replied message | `<Plug>NeomentRoomGoToReplied` | `<localleader>R` |
| Open thread | `<Plug>NeomentRoomOpenThread` | `<localleader>t` |
| Save attachment | `<Plug>NeomentRoomSaveAttachment` | `<localleader>s` |
| Upload attachment | `<Plug>NeomentRoomUploadAttachment` | `<localleader>u` |
| Upload image from clipboard | `<Plug>NeomentRoomUploadClipboardImage` | `<localleader>U` |
| Forward message | `<Plug>NeomentRoomForwardMessage` | `<localleader>w` |
| Toggle zoom of image under cursor | `<Plug>NeomentRoomToggleZoomImage` | `<localleader>z` |


#### Compose Buffer

Filetype: `neoment_compose`


| Description | Mapping | Default |
| --------------- | --------------- | --------------- |
| Send message | `<Plug>NeomentComposeSend` | `<CR>` |
| Send message (insert) | `<Plug>NeomentComposeSendInsert` | `<C-s>` |
| Abort compose | `<Plug>NeomentComposeAbort` | `<Esc>` |
| Abort compose (insert) | `<Plug>NeomentComposeAbortInsert` | `<C-c>` |


You can type `<C-x><C-o>` in insert mode, after typing `@`, to trigger the completion menu for mentions.

#### Space Buffer

Filetype: `neoment_space`


| Description | Mapping | Default |
| --------------- | --------------- | --------------- |
| Open room/space under cursor | `<Plug>NeomentSpaceEnter` | `<CR>` |
| Find room (open picker) | `<Plug>NeomentSpaceFind` | `<localleader>f` |
| Quit window (close the buffer) | `<Plug>NeomentSpaceQuit` | `<localleader>q` |
| Toggle room list | `<Plug>NeomentSpaceToggleRoomList` | `<localleader>l` |


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
