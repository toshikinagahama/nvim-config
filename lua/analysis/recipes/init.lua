-- 10. 分析レシピ: レシピを選ぶ → 列ピッカーで変数を選ぶ → 完成コードを挿入
--
-- レシピの追加: recipes/<言語>/<カテゴリ>.lua に書くだけ(フォルダごと自動で読み込む)
--   return {
--     lang = "r", cat = "生存",
--     { id = "km", name = "Kaplan-Meier", fields = { F.col("time", "観察期間") }, body = [=[...]=] },
--   }
-- 本文の置き換え:
--   {{df}}              データフレーム名
--   {{key}}             fields の値(col → `a` / "a"、cols → c("a", "b") / ["a", "b"]、input → 入力そのまま)
--   {{key_str}}         1列目を文字列で("a")
--   {{#key}}…{{/key}}   key が選ばれた時だけ残す(optional な欄用)。{{^key}}…{{/key}} は選ばれなかった時だけ
--     行ごと出し入れするなら、開始を行頭に・終了を次の行頭に置く: "{{#by}}group_by(by) %>%\n{{/by}}"
-- 入力欄の書き方は recipes/fields.lua
local A = require("analysis")
local M = {}

-- タブの並び順(ここに無いカテゴリは読み込み順で後ろに並ぶ)
local CAT_ORDER = {
  "前処理", "記述", "群比較", "反復測定", "相関", "回帰", "混合・GEE", "生存",
  "多変量", "信頼性", "診断・一致", "疫学", "検出力", "時系列", "周波数", "同期", "図", "seaborn", "plotly",
}

-- recipes/*/*.lua を全部読む
local function load_all()
  local list = {}
  local base = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
  local files = vim.fn.glob(base .. "*/*.lua", false, true)
  table.sort(files)
  for _, path in ipairs(files) do
    local lang_dir, file = path:match("([^/]+)/([^/]+)%.lua$")
    local mod = ("analysis.recipes.%s.%s"):format(lang_dir, file)
    package.loaded[mod] = nil
    local ok, t = pcall(require, mod)
    if not ok then
      vim.notify("レシピの読み込み失敗: " .. mod .. "\n" .. tostring(t), vim.log.levels.ERROR)
    else
      for _, r in ipairs(t) do
        r.lang = r.lang or t.lang or lang_dir
        r.cat = r.cat or t.cat or "その他"
        r.id = r.id or r.name
        r.fields = r.fields or {}
        -- pd を使う Python レシピには import pandas を補う
        if r.lang == "python" and r.body and r.body:find("pd%.") and not r.body:find("import pandas") then
          r.body = "import pandas as pd\n" .. r.body
        end
        list[#list + 1] = r
      end
    end
  end
  return list
end

M.list = load_all()

function M.reload()
  M.list = load_all()
  vim.notify(("レシピ %d 件を読み込み"):format(#M.list))
end

function M.category(r)
  return r.cat or "その他"
end

local function has(v)
  return v ~= nil and v ~= "" and not (type(v) == "table" and #v == 0)
end

local function fill(recipe, lang, df, values)
  if recipe.build then
    return recipe.build(lang, df, values)
  end
  local body = recipe.body
  -- {{#key}}…{{/key}} / {{^key}}…{{/key}}
  local prev
  repeat
    prev = body
    body = body:gsub("{{([#^])([%w_]+)}}(.-){{/%2}}", function(mark, key, inner)
      return ((mark == "#") == has(values[key])) and inner or ""
    end)
  until body == prev
  body = body:gsub("{{df}}", function()
    return df
  end)
  for _, f in ipairs(recipe.fields) do
    local v = values[f.key]
    if not has(v) and f.fallback then
      local text, str = f.fallback, A.q((f.fallback:gsub('^"(.*)"$', "%1")))
      body = body:gsub("{{" .. f.key .. "}}", function()
        return text
      end)
      body = body:gsub("{{" .. f.key .. "_str}}", function()
        return str
      end)
    elseif has(v) then
      local text, str
      if f.kind == "input" then
        text, str = v, A.q(v)
      else
        text, str = A.format_cols(lang, v, f.kind == "cols"), A.q(v[1])
      end
      body = body:gsub("{{" .. f.key .. "}}", function()
        return text
      end)
      body = body:gsub("{{" .. f.key .. "_str}}", function()
        return str
      end)
    end
  end
  return vim.split(body, "\n", { plain = true })
end

local function needs_df(recipe)
  if recipe.body and recipe.body:find("{{df}}", 1, true) then
    return true
  end
  for _, f in ipairs(recipe.fields) do
    if f.kind ~= "input" then
      return true
    end
  end
  return false
end

-- 欄を順番に埋める(列はピッカー、input は vim.ui.input)。途中で Esc → 中止
local function start(recipe, where, lang)
  local function run_fields(df)
    local values, i, n = {}, 0, #recipe.fields
    local function next_field()
      i = i + 1
      local f = recipe.fields[i]
      if not f then
        return A.insert_code(where, lang, fill(recipe, lang, df and df.name or "", values))
      end
      local title = ("%d/%d %s"):format(i, n, f.title) .. (f.optional and "(省略可)" or "")
      if f.kind == "input" then
        vim.ui.input({ prompt = title .. ": ", default = f.default and tostring(f.default) or nil }, function(v)
          if v == nil then
            return
          end
          if v == "" and not f.optional then
            v = f.default and tostring(f.default) or ""
          end
          values[f.key] = v
          next_field()
        end)
      else
        A.pick_columns(lang, df, function(cols)
          values[f.key] = f.kind == "col" and { cols[1] } or cols
          next_field()
        end, { title = title, single = f.kind == "col", optional = f.optional })
      end
    end
    next_field()
  end
  if not needs_df(recipe) then
    return run_fields(nil)
  end
  A.pick_df(lang, function(df)
    A.last_df[lang] = df.name
    run_fields(df)
  end)
end

-- レシピ一覧。Tab / S-Tab(または C-l / C-h)でカテゴリのタブを切り替え
function M.pick()
  local where = A.capture_pos()
  local lang = A.lang()
  local by_cat, cats = {}, {}
  for _, r in ipairs(M.list) do
    if r.lang == lang then
      local cat = M.category(r)
      local item = {
        text = cat .. " " .. r.name,
        label = r.name,
        detail = "[" .. cat .. "]",
        recipe = r,
        preview = { text = r.body, ft = lang },
      }
      if not by_cat[cat] then
        by_cat[cat] = {}
        cats[#cats + 1] = cat
      end
      table.insert(by_cat[cat], item)
    end
  end
  local rank = {}
  for i, c in ipairs(CAT_ORDER) do
    rank[c] = i
  end
  local first = {}
  for i, c in ipairs(cats) do
    first[c] = i
  end
  table.sort(cats, function(a, b)
    local ra, rb = rank[a] or (100 + first[a]), rank[b] or (100 + first[b])
    return ra < rb
  end)
  by_cat["全部"] = {}
  for _, c in ipairs(cats) do
    vim.list_extend(by_cat["全部"], by_cat[c])
  end
  table.insert(cats, 1, "全部")

  local idx = 1
  -- タブ列は幅に収まる分だけ、今のタブを中心に表示。はみ出す側に ‹ / › を付ける
  local function title(width)
    local W = vim.fn.strdisplaywidth
    local head = ("レシピ(%s) %d/%d "):format(lang, idx, #cats)
    -- 初回は窓がまだ無いので、default レイアウトの入力欄の幅(全体 80% の左半分)で見積もる
    local avail = (width or math.floor(vim.o.columns * 0.4)) - W(head) - 6
    local label = function(i)
      return i == idx and ("【" .. cats[i] .. " " .. #by_cat[cats[i]] .. "】") or cats[i]
    end
    local lo, hi = idx, idx
    local used = W(label(idx))
    local grew = true
    while grew do
      grew = false
      for _, side in ipairs({ 1, -1 }) do
        local j = side == 1 and hi + 1 or lo - 1
        if cats[j] and used + 1 + W(label(j)) + 4 <= avail then
          used = used + 1 + W(label(j))
          if side == 1 then hi = j else lo = j end
          grew = true
        end
      end
    end
    local parts = {}
    for i = lo, hi do
      parts[#parts + 1] = label(i)
    end
    return head .. (lo > 1 and "‹ " or "") .. table.concat(parts, " ") .. (hi < #cats and " ›" or "")
  end
  local function win_width(p)
    local ok, w = pcall(function()
      return vim.api.nvim_win_get_width(p.input.win.win)
    end)
    return ok and w or nil
  end
  local function switch(step)
    return function(p)
      idx = (idx - 1 + step) % #cats + 1
      p.opts.items = by_cat[cats[idx]]
      p.title = title(win_width(p))
      p:find()
    end
  end
  local mode = { "i", "n" }
  A.picker({
    title = title(),
    items = by_cat["全部"],
    actions = { cat_next = switch(1), cat_prev = switch(-1) },
    keys = {
      ["<Tab>"] = { "cat_next", mode = mode },
      ["<S-Tab>"] = { "cat_prev", mode = mode },
      ["<C-l>"] = { "cat_next", mode = mode },
      ["<C-h>"] = { "cat_prev", mode = mode },
      -- 大文字は入力欄では文字として打つので、ノーマルモード(Esc 後)だけ
      ["L"] = { "cat_next", mode = { "n" } },
      ["H"] = { "cat_prev", mode = { "n" } },
    },
    on_pick = function(sel)
      start(sel[1].recipe, where, lang)
    end,
  })
end

-- 一覧を飛ばして id(または名前)で実行。今のバッファの言語のレシピを探す
function M.run(id)
  local lang = A.lang()
  for _, r in ipairs(M.list) do
    if r.lang == lang and (r.id == id or r.name == id) then
      return start(r, A.capture_pos(), lang)
    end
  end
  vim.notify(("レシピなし(%s): %s"):format(lang, id), vim.log.levels.WARN)
end

return M
