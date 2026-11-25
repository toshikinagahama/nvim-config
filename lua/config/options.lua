-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- データ分析環境(Mac / Pi / 職場サーバ 共通)

-- molten 用 Python(pynvim, jupyter_client 入り)。マシンごとの venv を自動選択
for _, python in ipairs({
  vim.env.NVIM_PYTHON or "",
  vim.fn.expand("~/python_settings/.venv/bin/python"), -- 職場サーバ
  vim.fn.expand("~/.venvs/neovim/bin/python"), -- Mac / Pi
}) do
  if python and python ~= "" and vim.fn.executable(python) == 1 then
    vim.g.python3_host_prog = python
    break
  end
end

-- カレント以上の .venv にカーネル定義があれば、そのプロジェクトのカーネルを使う
local venv_kernels = vim.fs.find(".venv/share/jupyter", { upward = true, type = "directory" })[1]
if venv_kernels then
  vim.env.JUPYTER_PATH = venv_kernels
end

-- Mason の bin を PATH の先頭に(古い tree-sitter CLI 等より Mason 版を優先)
vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin:" .. vim.env.PATH

-- figviewer: Python の図/表をブラウザ(http://localhost:8766)に表示
-- 実体は ~/.ipython/profile_default/startup/10-figviewer.py。nvim から起動したカーネルだけ有効
vim.env.FIGVIEWER = "1"

-- SSH 越しのときは OSC52 で手元PCのクリップボードへコピー
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
  vim.opt.clipboard = "unnamedplus"
end

-- WSL: share the clipboard with Windows (win32yank.exe if installed, otherwise clip.exe / powershell)
if vim.fn.has("wsl") == 1 and not vim.env.SSH_TTY then
  if vim.fn.executable("win32yank.exe") == 0 then
    vim.g.clipboard = {
      name = "WSL clip.exe",
      copy = { ["+"] = "clip.exe", ["*"] = "clip.exe" },
      paste = {
        ["+"] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r", ""))',
        ["*"] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r", ""))',
      },
      cache_enabled = 0,
    }
  end
  vim.opt.clipboard = "unnamedplus"
end

vim.opt.number = true
vim.opt.relativenumber = false -- 行番号は絶対表示
vim.opt.wrap = true -- 画面端で折り返し(j/k は LazyVim 既定で gj/gk 動作)
vim.opt.linebreak = true -- 単語の途中で折らない
vim.opt.breakindent = true -- 折り返し行もインデントを揃える

-- マシン固有・職場固有の設定は lua/config/local.lua に(.gitignore 済み、無ければ何もしない)
pcall(require, "config.local")
