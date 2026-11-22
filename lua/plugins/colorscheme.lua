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
      on_highlights = function(hl, c)
        -- カーソル下の記号と同じものを LSP が塗る(document highlight)。既定は背景色付きで、
        -- R の languageserver はコメント行まで塗ることがあり目立つ → 下線だけにする
        for _, g in ipairs({ "LspReferenceText", "LspReferenceRead", "LspReferenceWrite" }) do
          hl[g] = { underline = true, sp = c.fg_gutter }
        end
      end,
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight" } },
}
-- 以前の配色:
--   { "rebelot/kanagawa.nvim", priority = 1000, opts = { theme = "wave", transparent = true } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "kanagawa" } },
--   { "loctvl842/monokai-pro.nvim", priority = 1000, opts = { filter = "classic" } },
--   { "LazyVim/LazyVim", opts = { colorscheme = "monokai-pro-classic" } },
