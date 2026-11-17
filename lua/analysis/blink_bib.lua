-- blink.cmp の補完ソース: qmd / md で [@ と打つと .bib の引用キーを候補に出す
--   .bib の探し方(上から順に、見つかったもの全部):
--     1. このファイルの YAML の bibliography:(文字列 / リスト)
--     2. 上の階層の _quarto.yml の bibliography:
--     3. どちらにも無ければ、このファイルのフォルダとプロジェクト直下の *.bib
--   候補は著者名・年でも絞り込める(例: [@smith → Smith の文献)。.bib は更新時刻で読み直す
local M = {}

local FILETYPES = { quarto = true, markdown = true, rmd = true }
local cache = {} -- path -> { mtime, entries }

-- ---------------------------------------------------------------------------
-- .bib の読み込み
-- ---------------------------------------------------------------------------

local function clean(v)
  v = v:gsub("\\[%a]+%s*", ""):gsub("[{}]", ""):gsub("%s+", " ")
  return vim.trim(v)
end

-- pos は "=" の後ろ。値と、値の次の位置を返す
local function read_value(text, pos)
  pos = text:find("%S", pos) or #text + 1
  local c = text:sub(pos, pos)
  if c == "{" then
    local depth, i = 0, pos
    while i <= #text do
      local ch = text:sub(i, i)
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then
          return text:sub(pos + 1, i - 1), i + 1
        end
      end
      i = i + 1
    end
    return text:sub(pos + 1), #text + 1
  elseif c == '"' then
    local i = pos + 1
    while i <= #text do
      local ch = text:sub(i, i)
      if ch == "\\" then
        i = i + 1
      elseif ch == '"' then
        return text:sub(pos + 1, i - 1), i + 1
      end
      i = i + 1
    end
    return text:sub(pos + 1), #text + 1
  end
  local s, e = text:find("^[^,}]*", pos)
  return text:sub(s, e), e + 1
end

function M.parse(text)
  local entries, pos = {}, 1
  while true do
    local s, e, typ, key = text:find("@(%a+)%s*{%s*([^,%s{}]+)%s*,", pos)
    if not s then
      break
    end
    typ = typ:lower()
    local fields, i = {}, e + 1
    -- エントリの終わり( } )まで フィールド名 = 値 を読む
    while true do
      local fs, fe, name = text:find("^%s*([%w_%-]+)%s*=", i)
      if not fs then
        break
      end
      local value, nxt = read_value(text, fe + 1)
      fields[name:lower()] = clean(value)
      i = nxt
      local comma = text:find("^%s*,", i)
      if comma then
        i = text:find(",", i) + 1
      else
        break
      end
    end
    if typ ~= "comment" and typ ~= "string" and typ ~= "preamble" then
      entries[#entries + 1] = { key = key, type = typ, fields = fields }
    end
    pos = i
  end
  return entries
end

local function read_bib(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return {}
  end
  local c = cache[path]
  if c and c.mtime == stat.mtime.sec then
    return c.entries
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  local entries = ok and M.parse(table.concat(lines, "\n")) or {}
  cache[path] = { mtime = stat.mtime.sec, entries = entries }
  return entries
end

-- ---------------------------------------------------------------------------
-- .bib の場所
-- ---------------------------------------------------------------------------

-- YAML の行から bibliography: の値(文字列 / リスト)を取り出す
function M.yaml_bibs(lines)
  local out, in_list = {}, false
  for _, l in ipairs(lines) do
    local v = l:match("^%s*bibliography:%s*(.-)%s*$")
    if v then
      in_list = false
      if v == "" then
        in_list = true
      elseif v:match("^%[") then
        for item in v:gmatch("[^%[%],]+") do
          item = vim.trim(item):gsub("^[\"']", ""):gsub("[\"']$", "")
          if item ~= "" then
            out[#out + 1] = item
          end
        end
      else
        out[#out + 1] = (v:gsub("^[\"']", ""):gsub("[\"']$", ""))
      end
    elseif in_list then
      local item = l:match("^%s*%-%s*(.-)%s*$")
      if item then
        out[#out + 1] = (item:gsub("^[\"']", ""):gsub("[\"']$", ""))
      elseif l:match("^%S") then
        in_list = false
      end
    end
  end
  return out
end

local function front_matter(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 200, false)
  if lines[1] ~= "---" then
    return {}
  end
  for i = 2, #lines do
    if lines[i] == "---" or lines[i] == "..." then
      return vim.list_slice(lines, 2, i - 1)
    end
  end
  return {}
end

function M.bib_files(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local dir = file ~= "" and vim.fs.dirname(file) or vim.fn.getcwd()
  local found, seen = {}, {}
  local function add(path)
    path = vim.fs.normalize(path)
    if not seen[path] and vim.uv.fs_stat(path) then
      seen[path] = true
      found[#found + 1] = path
    end
  end
  local function abs(base, p)
    p = vim.fn.expand(p)
    return p:sub(1, 1) == "/" and p or (base .. "/" .. p)
  end
  for _, p in ipairs(M.yaml_bibs(front_matter(buf))) do
    add(abs(dir, p))
  end
  local qy = vim.fs.find("_quarto.yml", { path = dir, upward = true })[1]
  if qy then
    local qdir = vim.fs.dirname(qy)
    for _, p in ipairs(M.yaml_bibs(vim.fn.readfile(qy))) do
      add(abs(qdir, p))
    end
  end
  if #found == 0 then
    local root = qy and vim.fs.dirname(qy)
      or vim.fs.root(dir, { ".git", "_quarto.yml" })
      or dir
    for _, d in ipairs({ dir, root }) do
      for _, p in ipairs(vim.fn.glob(d .. "/*.bib", false, true)) do
        add(p)
      end
    end
  end
  return found
end

-- ---------------------------------------------------------------------------
-- 候補
-- ---------------------------------------------------------------------------

local function surname(author)
  local first = vim.split(author or "", "%s+and%s+")[1] or ""
  -- 「姓, 名」はカンマの前。カンマ無しは英語なら最後の語、日本語(マルチバイト)なら最初の語が姓
  local last = first:match("^([^,]+),")
    or (first:find("[\128-\255]") and first:match("^(%S+)"))
    or first:match("(%S+)$")
    or first
  return vim.trim(last), author and author:find("%sand%s") ~= nil
end

function M.item(e)
  local f = e.fields
  local name, many = surname(f.author or f.editor)
  local year = f.year or (f.date and f.date:match("%d%d%d%d")) or ""
  local who = name ~= "" and (name .. (many and " et al." or "")) or ""
  local venue = f.journal or f.journaltitle or f.booktitle or f.publisher or ""
  local doc = {}
  if f.title then
    doc[#doc + 1] = "**" .. f.title .. "**"
  end
  doc[#doc + 1] = table.concat(vim.tbl_filter(function(x)
    return x ~= ""
  end, { f.author or "", year ~= "" and ("(" .. year .. ")") or "", venue }), "  ")
  if f.doi then
    doc[#doc + 1] = "doi: " .. f.doi
  end
  return {
    label = e.key,
    insertText = e.key,
    filterText = table.concat({ e.key, name, year }, " "),
    kind = require("blink.cmp.types").CompletionItemKind.Reference,
    labelDetails = { description = vim.trim(who .. " " .. year) },
    documentation = { kind = "markdown", value = table.concat(doc, "\n\n") },
  }
end

-- [@ / ; @ / 行頭・空白の後の @ の直後だけ(メールアドレスには出さない)
function M.in_citation(line, start_col)
  if line:sub(start_col - 1, start_col - 1) ~= "@" then
    return false
  end
  local before = start_col >= 3 and line:sub(start_col - 2, start_col - 2) or ""
  return before == "" or before:match("[%[;%s%-]") ~= nil
end

-- ---------------------------------------------------------------------------
-- blink.cmp のソース
-- ---------------------------------------------------------------------------

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  return FILETYPES[vim.bo.filetype] == true
end

function M:get_trigger_characters()
  return { "@" }
end

function M:get_completions(ctx, callback)
  local empty = { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
  if not M.in_citation(ctx.line, ctx.bounds.start_col) then
    callback(empty)
    return
  end
  local items = {}
  for _, path in ipairs(M.bib_files(ctx.bufnr)) do
    for _, e in ipairs(read_bib(path)) do
      items[#items + 1] = M.item(e)
    end
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
