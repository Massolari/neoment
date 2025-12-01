# Neoment.nvim

A Matrix client for Neovim, bringing chat functionality directly into your editor.

> **⚠️ Warning:** This plugin is currently in beta and under active development. The API may change without prior notice. Use at your own risk and expect breaking changes between updates.

## Description

Neoment.nvim is a Matrix protocol client implementation for Neovim that allows you to chat, and stay connected without leaving your editor.

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
	"douglasmassolari/neoment.nvim",
	config = function()
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
	"douglasmassolari/neoment.nvim",
	config = function()
		vim.g.neoment = {
			save_session = true,
		}
	end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'douglasmassolari/neoment.nvim'

" Optional configuration
let g:neoment = {'save_session': v:true}
```

## Usage

### First Time Setup

1. Open Neovim and run `:Neoment login` to authenticate with your Matrix homeserver
1. Provide your username and password
1. The plugin will automatically sync and display your rooms

### Commands

- `:Neoment login` - Login to your Matrix account
- `:Neoment logout` - Logout and clear session data
- `:Neoment rooms` - Toggle the rooms list sidebar
- `:Neoment start sync` - Start syncing messages
- `:Neoment stop sync` - Stop syncing messages
_ `:Neoment join <room_id_or_alias>` - Join a room by its ID or alias

### Basic Workflow

1. **View Rooms:** Use `:Neoment` to open the room list
1. **Open a Room:** Press `<CR>` (Enter) on a room to open it
1. **Send Messages:** Press `<CR>` in a room to compose a message
1. **Navigate:** Use standard Neovim navigation keys to browse messages
1. **Threads:** Use `<localleader>t` to open threads for organized conversations

### Configuration

```lua
vim.g.neoment = {
	-- Save session data to disk (default: true)
	save_session = true,
}
```

### Key Bindings

#### Rooms Buffer

- `<CR>` - Open selected room
- `<Tab>` - Toggle fold at cursor
- `q` - Close rooms list
- `<localleader>a` - Toggle favorite
- `<localleader>f` - Find room (picker)
- `<localleader>l` - Toggle low priority
- `<localleader>r` - Toggle read/unread
- `<localleader>s` - Sync rooms

#### Room Buffer

- `<CR>` - Compose/send message
- `<localleader>a` - React to message
- `<localleader>d` - Redact (delete) message
- `<localleader>e` - Edit message
- `<localleader>f` - Find room (picker)
- `<localleader>q` - Quit room (close the buffer)
- `<localleader>l` - Toggle room list
- `<localleader>L` - Leave room
- `<localleader>m` - Set read marker
- `<localleader>o` - Open attachment
- `<localleader>p` - Load previous messages
- `<localleader>r` - Reply to message
- `<localleader>R` - Go to replied message
- `<localleader>t` - Open thread
- `<localleader>s` - Save attachment
- `<localleader>u` - Upload attachment
- `<localleader>U` - Upload image from clipboard
- `<localleader>w` - Forward message
- `<localleader>z` - Toggle zoom image

## Inspiration

Neoment.nvim draws inspiration from some excellent Matrix clients:

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
