-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

if vim.g.vscode then
  -- Space+e: toggle explorer sidebar (LazyVim-like)
  vim.keymap.set("n", "<leader>e", function()
    require("vscode").action("workbench.action.toggleSidebarVisibility")
  end, { desc = "Toggle Explorer" })
end
