-- レシピの入力欄
--   F.col("key", "見出し")              1列     → R: `a`          / Python: "a"
--   F.cols("key", "見出し")             複数列  → R: c("a", "b")  / Python: ["a", "b"]
--   F.input("key", "見出し", "初期値")   文字入力 → そのまま埋め込む(数値・式・オブジェクト名など)
-- 第3(input は第4)引数の opts:
--   optional = true   列なら一覧の先頭に「(なし)」が出る / input なら空欄で飛ばせる
--                     本文では {{#key}}…{{/key}}(ある時だけ)/ {{^key}}…{{/key}}(無い時だけ)で書き分ける
--   fallback = "全体"  省略した時に {{key}} へ入れる文字(そのまま埋め込む。Python なら '"全体"' のように引用符ごと)
local F = {}

local function field(kind, key, title, opts)
  return vim.tbl_extend("force", { key = key, kind = kind, title = title }, opts or {})
end

function F.col(key, title, opts)
  return field("col", key, title, opts)
end

function F.cols(key, title, opts)
  return field("cols", key, title, opts)
end

function F.input(key, title, default, opts)
  return field("input", key, title, vim.tbl_extend("force", { default = default }, opts or {}))
end

return F
