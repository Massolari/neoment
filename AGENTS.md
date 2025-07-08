# Neoment.nvim - Agent Guidelines

## Build/Test Commands
- `make test` - Run all tests using Plenary/Busted
- `make test-watch` - Run tests in watch mode
- Tests use Plenary test framework with luassert assertions

## Code Style
- Use tabs for indentation
- Module pattern: `local M = {}` and `return M`
- Import style: `local module = require("neoment.module")`
- Function docs: Use `---` comments with `@param` and `@return` annotations
- Type annotations: Use `--- @type` and `--- @class` for LSP support
- Error handling: Use custom error monad pattern from `neoment.error`
- Async patterns: Use `vim.schedule()` for UI updates from async contexts
- Naming: snake_case for variables/functions, PascalCase for classes
- File organization: One module per file, grouped by functionality
- Tests: Use `describe()` and `it()` with descriptive names
- Vim API: Prefer `vim.api.*` over legacy `vim.fn.*` where possible

## Architecture
- Matrix client implementation for Neovim
- Modular design with separate concerns (sync, rooms, storage, etc.)
- Custom error handling with Result-like pattern
- Async operation handling with proper scheduling