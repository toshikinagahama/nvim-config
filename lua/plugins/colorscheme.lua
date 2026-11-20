-- 配色: tokyonight(LazyVim 同梱)。style = "night"(一番暗い) / "moon" / "storm" / "day"
-- 背景は透過(WezTerm の window_background_opacity を透かす)。WezTerm 側は color_scheme = "Tokyo Night"
return {
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    opts = {
      style = "night",
      transparent = true,
      styles = { sidebars = "transparent", floats = "transparent" },
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },
}
-- 以前の配色:
--   { "rebelot/kanagawa.nvim", priority = 1000, opts = { theme = "wave", transparent = true } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "kanagawa" } },
--   { "loctvl842/monokai-pro.nvim", priority = 1000, opts = { filter = "classic" } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "monokai-pro-classic" } },
