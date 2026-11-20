-- pptx 用: Quarto の相互参照付き表({#tbl-} / tbl-cap)は pptx だと表ごと消える(Quarto の仕様)
--   → 普通の表 + キャプション「Table 1: 〜」に置き換える。キャプションを表の上へ移すのは pptx_post.py
-- マーカー(==文字== / [文字]{.mark}、要 from: markdown+mark)は pptx に無いので SmallCaps で目印 → pptx_post.py が黄色ハイライトに
-- columns の下に書いた文(コメント等)は pptx だと次のスライドへ送られる
--   → 目印付きで文字だけのカラム末尾に入れ、pptx_post.py がカラムの下(全幅)へ移す
--     (両カラムとも図/表ならノートに退避して後処理でスライドへ)
-- columns の下に図・表を書いた → 図・表から先は次スライドへ(同じタイトル)
-- 1カラムに図・表が2個以上(図+表など)だと pandoc が2個目以降を捨てる → 次スライドへ送る
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

-- 図・表1個分のまとまり(チャンク出力 / 相互参照付き図表 / 素の図・表)
local function has_visual(b)
  local v = false
  pandoc.walk_block(b, {
    Image = function() v = true end,
    Table = function() v = true end,
    Figure = function() v = true end,
  })
  return v
end

local function is_visual_unit(b)
  if b.t == "Figure" or b.t == "Table" or b.t == "FloatRefTarget" then return true end
  if b.t == "Para" or b.t == "Plain" then
    for _, x in ipairs(b.content) do if x.t == "Image" then return true end end
    return false
  end
  if b.t == "Div" then
    if b.classes:includes("cell-output-display") or b.identifier:match("^fig%-") or b.identifier:match("^tbl%-") then
      return has_visual(b)
    end
  end
  return false
end

-- 1カラムに図・表が2個以上あると pandoc は2個目以降を黙って捨てる(図+表だと表が消える)
--   → 最初の1個だけ残し、残りは取り出す(columns の後ろに改スライドで並べる)
local function take_extras(blocks, st)
  local out = pandoc.List()
  for _, b in ipairs(blocks) do
    if is_visual_unit(b) then
      if st.seen then st.extras:insert(b) else st.seen = true; out:insert(b) end
    elseif b.t == "Div" then
      b.content = take_extras(b.content, st)
      out:insert(b)
    else
      out:insert(b)
    end
  end
  return out
end

local function columns_below(blocks)
  local out, i = pandoc.List(), 1
  while i <= #blocks do
    local b = blocks[i]
    out:insert(b)
    i = i + 1
    if b.t == "Div" and b.classes:includes("columns") then
      local extras = pandoc.List()
      for _, c in ipairs(b.content) do
        if c.t == "Div" and c.classes:includes("column") then
          local st = { seen = false, extras = pandoc.List() }
          c.content = take_extras(c.content, st)
          extras:extend(st.extras)
        end
      end
      local tail = pandoc.List()
      -- columns の下に図・表(チャンク出力)が来たら、そこから先は次スライドへ(カラム内やノートに入れると消える)
      local rest = false
      while i <= #blocks and not is_break(blocks[i]) do
        if has_visual(blocks[i]) then rest = true break end
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
      -- 取り出した図・表は1個ずつ改スライド(タイトルは pptx_post.py が「〜（続き）」に)
      for _, e in ipairs(extras) do
        out:insert(pandoc.HorizontalRule())
        if e.t == "Div" and not e.identifier:match("^fig%-") and not e.identifier:match("^tbl%-") then
          out:extend(flatten(e)) -- Div 内の表は pptx で落ちる
        else
          out:insert(e)
        end
      end
      if rest then out:insert(pandoc.HorizontalRule()) end
    end
  end
  return out
end

-- 図・表の後に続く文 → pandoc は次スライドへ送る(タイトル無し)
--   → 目印付きでノートに退避し、pptx_post.py が図・表の下へ置く(図は縮める)
local function notes_below(tail)
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
  return pandoc.Div(nd, pandoc.Attr("", { "notes" }))
end

local function is_text_block(b)
  if b.t == "Div" and (b.classes:includes("notes") or b.classes:includes("columns")) then return false end
  return not is_break(b) and not has_visual(b)
end

local function text_after_visual(blocks)
  local out, i = pandoc.List(), 1
  while i <= #blocks do
    local b = blocks[i]
    out:insert(b)
    i = i + 1
    if not (b.t == "Div" and b.classes:includes("columns")) and has_visual(b) then
      local tail = pandoc.List()
      while i <= #blocks and is_text_block(blocks[i]) do
        tail:insert(blocks[i])
        i = i + 1
      end
      local txt = false
      for _, t in ipairs(tail) do
        if pandoc.utils.stringify(t):match("%S") and not (t.t == "Div" and t.classes:includes("cell")) then txt = true end
      end
      if txt then out:insert(notes_below(tail)) else out:extend(tail) end
    end
  end
  return out
end

return {
  {
    Pandoc = function(doc)
      doc.blocks = text_after_visual(columns_below(doc.blocks))
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
