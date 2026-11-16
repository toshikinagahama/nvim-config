-- pptx 用: Quarto の相互参照付き表({#tbl-} / tbl-cap)は pptx だと表ごと消える(Quarto の仕様)
--   → 普通の表 + キャプション「Table 1: 〜」に置き換える。キャプションを表の上へ移すのは pptx_post.py
-- マーカー(==文字== / [文字]{.mark}、要 from: markdown+mark)は pptx に無いので SmallCaps で目印 → pptx_post.py が黄色ハイライトに
-- columns の下に書いた文(コメント等)は pptx だと次のスライドへ送られる
--   → 目印付きで文字だけのカラム末尾に入れ、pptx_post.py がカラムの下(全幅)へ移す
--     (両カラムとも図/表ならノートに退避して後処理でスライドへ)
-- 使い方(YAML): filters: [{path: templates/pptx-tables.lua, at: pre-render}]
if not FORMAT:match("pptx") then return {} end

local tbl_title, sep = "Table", ": "

local function to_inlines(x)
  if x == nil then return pandoc.Inlines({}) end
  local t = pandoc.utils.type(x)
  if t == "Inlines" then return x end
  if t == "Inline" then return pandoc.Inlines({ x }) end
  if t == "Block" then x = pandoc.Blocks({ x }) end
  if t == "Blocks" or t == "List" or t == "Block" then return pandoc.utils.blocks_to_inlines(x) end
  return pandoc.Inlines({ pandoc.Str(pandoc.utils.stringify(x)) })
end

-- Div(cell-output-display 等)は中身だけにする(Div 内の表は pptx で落ちる)
local function flatten(blocks)
  if pandoc.utils.type(blocks) == "Block" then blocks = { blocks } end
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if b.t == "Div" then out:extend(flatten(b.content)) else out:insert(b) end
  end
  return out
end

local BELOW = "@@COLUMNS_BELOW@@"

local function is_break(b)
  return b.t == "Header" or b.t == "HorizontalRule"
end

local function text_only(div)
  local ok = true
  pandoc.walk_block(div, {
    Image = function() ok = false end,
    Table = function() ok = false end,
    Figure = function() ok = false end,
    Div = function(d) if d.classes:includes("cell") or d.classes:includes("cell-output-display") then ok = false end end,
  })
  return ok
end

local function columns_below(blocks)
  local out, i = pandoc.List(), 1
  while i <= #blocks do
    local b = blocks[i]
    out:insert(b)
    i = i + 1
    if b.t == "Div" and b.classes:includes("columns") then
      local tail = pandoc.List()
      while i <= #blocks and not is_break(blocks[i]) do
        tail:insert(blocks[i])
        i = i + 1
      end
      if #tail > 0 then
        -- 図・表・チャンク出力があるカラムに文を足すと pandoc が文を捨てる → 文字だけのカラムを選ぶ
        local target = nil
        for _, c in ipairs(b.content) do
          if c.t == "Div" and c.classes:includes("column") and text_only(c) then target = c break end
        end
        if target then
          target.content:insert(pandoc.Para({ pandoc.Str(BELOW) }))
          target.content:extend(tail)
        else -- 両カラムとも図/表: 発表者ノートに目印付きで退避 → pptx_post.py がスライドへ戻す
          local nd = pandoc.List({ pandoc.Para({ pandoc.Str(BELOW) }) })
          for _, tb in ipairs(tail) do -- ノートでは箇条書きの記号が消えるので「• 」を文字で付ける
            if tb.t == "BulletList" or tb.t == "OrderedList" then
              for n, item in ipairs(tb.content) do
                local mark = tb.t == "BulletList" and "• " or (n .. ". ")
                local inl = pandoc.Inlines({ pandoc.Str(mark) })
                inl:extend(pandoc.utils.blocks_to_inlines(item))
                nd:insert(pandoc.Para(inl))
              end
            else
              nd:insert(tb)
            end
          end
          out:insert(pandoc.Div(nd, pandoc.Attr("", { "notes" })))
        end
      end
    end
  end
  return out
end

return {
  {
    Pandoc = function(doc)
      doc.blocks = columns_below(doc.blocks)
      return doc
    end,
  },
  {
    Meta = function(m)
      local c = m.crossref
      if c and c["tbl-title"] then tbl_title = pandoc.utils.stringify(c["tbl-title"]) end
      if c and c["title-delim"] then sep = pandoc.utils.stringify(c["title-delim"]) .. " " end
    end,
  },
  {
    Span = function(el)
      if el.classes:includes("mark") then return pandoc.SmallCaps(el.content) end
    end,
    FloatRefTarget = function(el)
      if el.type ~= "Table" then return nil end
      local cap = pandoc.Inlines({})
      local n = el.order and el.order.order
      if n then cap:extend({ pandoc.Str(tbl_title .. "\u{a0}" .. n .. sep) }) end
      cap:extend(to_inlines(el.caption_long))
      local blocks = flatten(el.content)
      for _, b in ipairs(blocks) do
        if b.t == "Table" then
          b.caption = pandoc.Caption({ pandoc.Plain(cap) })
          b.attr = pandoc.Attr()
          return blocks -- id 付き Div で返すと Quarto が再び float 扱いして消す
        end
      end
      blocks:insert(1, pandoc.Para(cap)) -- 表でない出力(print(df) 等)はキャプションを段落で
      return blocks
    end,
  },
}
