-- 保存時整形: Python=Ruff、R=Air、qmd=コードブロックごとに言語判定して両方
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "ruff_format" },
        r = { "air" },
        quarto = { "injected" },
      },
    },
  },
}
