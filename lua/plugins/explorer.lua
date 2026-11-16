-- otter が書き出す一時ファイル(*.otter.R / *.otter.py)を explorer・ファイル検索から隠す
return {
  {
    "folke/snacks.nvim",
    opts = {
      explorer = { replace_netrw = false },
      picker = {
        sources = {
          explorer = { exclude = { "*.otter.*" } },
          files = { exclude = { "*.otter.*" } },
        },
      },
    },
  },
}
