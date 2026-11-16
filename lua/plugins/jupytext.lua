-- .ipynb を "# %%" 形式のスクリプトとして開く(保存時に .ipynb へ書き戻し、既存の出力は保持)
-- 要 jupytext CLI (uv tool install jupytext)。言語はノートブックの kernelspec で決まる
return {
  "GCBallesteros/jupytext.nvim",
  lazy = false,
  opts = {
    style = "percent",
    output_extension = "auto",
    -- R ノートブックは jupytext が拡張子 .R を要求するため明示(.r だと変換に失敗する)
    custom_language_formatting = {
      R = { extension = "R", style = "percent", force_ft = "r" },
      r = { extension = "R", style = "percent", force_ft = "r" },
    },
  },
}
