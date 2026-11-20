-- 配色: tokyonight(LazyVim 同梱)。style = "moon" / "storm" / "night" / "day"
return {
  { "folke/tokyonight.nvim", priority = 1000, opts = { style = "moon" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },
}
-- 以前の配色:
--   { "rebelot/kanagawa.nvim", priority = 1000, opts = { theme = "wave" } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "kanagawa" } },
--   { "loctvl842/monokai-pro.nvim", priority = 1000, opts = { filter = "classic" } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "monokai-pro-classic" } },
