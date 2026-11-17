-- qmd / md で [@ と打つと .bib の引用キーを補完(実装は lua/analysis/blink_bib.lua)
return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      sources = {
        default = { "bib" },
        providers = {
          bib = {
            name = "Bib",
            module = "analysis.blink_bib",
            score_offset = 20, -- 引用の位置ではバッファの単語より上に出す
          },
        },
      },
    },
  },
}
