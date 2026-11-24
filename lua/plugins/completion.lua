-- 補完候補を勝手に選択しない(Enter は改行のまま。候補を使う時だけ Tab / Ctrl-n で選んでから Enter)
return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      completion = {
        list = {
          selection = {
            preselect = false, -- 一覧が出ても先頭を選んだ状態にしない
            auto_insert = true, -- Tab / Ctrl-n で選んだ候補は本文に仮入力して見せる
          },
        },
      },
    },
  },
}
