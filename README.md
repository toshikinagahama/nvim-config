# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Setting up on another PC (Windows WSL / Ubuntu)

```bash
# 1. Prerequisites (Ubuntu on WSL)
sudo apt update
sudo apt install -y git curl unzip build-essential gdb cmake ripgrep fd-find nodejs npm python3-venv
# Neovim 0.12 or later is required (lazy-lock.json assumes 0.12)
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz && sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim

# 2. Get this config
mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null
git clone https://github.com/toshikinagahama/nvim-config ~/.config/nvim
nvim   # on first launch, lazy.nvim / Mason install plugins, clangd, clang-format and codelldb automatically
```

- Clipboard: inside WSL, yanks go to the Windows clipboard (`clip.exe`). Installing `win32yank.exe` on the PATH is faster and is used when present.
- Machine-specific settings go in `lua/config/local.lua` (not tracked by git).
- To update: `cd ~/.config/nvim && git pull`, then `:Lazy restore` (matches the versions in lazy-lock.json).

## C / C++

- LSP: clangd (completion, diagnostics, clang-tidy). For a CMake project, `compile_commands.json` is generated in `build/`.
  For a single file, it works without one (`-std=c++20` / `-std=c17` can be set in `.clangd` or `compile_flags.txt`).
- Formatting: clang-format (on save). Put a `.clang-format` file in the project root to change the style.
- `\r`: build and run the current file (`g++ -std=c++20 -Wall -Wextra -g` → `build/<name>`). If there is a CMakeLists.txt, run cmake configure + build
- `\b`: build only
- Debugging (nvim-dap + codelldb): `<leader>db` breakpoint, `<leader>dc` start/continue, `<leader>di`/`<leader>do` step
- `<leader>ch`: switch between header and source (clangd)
