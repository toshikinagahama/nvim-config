-- 分析補助(追加分): 型変換コード / 表→Word / 相互参照 / ファイル→読込コード / Excel 貼り付け→df
-- キー割り当ては plugins/analysis.lua。コード生成部分は純粋関数(テストしやすいよう M.gen_* に分離)
local M = {}
local function A() return require("analysis") end

local function notify(msg, level) A().notify(msg, level) end
-- 文字列リテラル(改行/タブはエスケープ: バッファの1行に収める)
local q = function(s) return (A().q(s):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")) end

-- ---------------------------------------------------------------------------
-- 共通: プロジェクトルート(here::here と Python の ROOT が同じ場所を指すように揃える)
-- ---------------------------------------------------------------------------
local root_markers = { ".here", ".git", "DESCRIPTION", "pyproject.toml" }

function M.root(file)
  file = file and file ~= "" and file or (vim.fn.getcwd() .. "/_")
  for dir in vim.fs.parents(file) do
    for _, m in ipairs(root_markers) do
      if vim.uv.fs_stat(dir .. "/" .. m) then return dir end
    end
    if #vim.fn.glob(dir .. "/*.Rproj", false, true) > 0 then return dir end
  end
  return vim.fn.getcwd()
end

local function relpath(root, path)
  root = vim.fs.normalize(root):gsub("/$", "")
  path = vim.fs.normalize(path)
  if path:sub(1, #root + 1) == root .. "/" then return path:sub(#root + 2) end
  -- macOS: 濁点などの Unicode 正規化(NFC/NFD)が root と path で違うと文字列比較が一致しない
  --   → 親を辿り、root と同じ実体(dev+ino)のディレクトリを探して相対化する
  local rs = vim.uv.fs_stat(root)
  if rs then
    local parts = {}
    local dir = path
    while true do
      local parent = vim.fs.dirname(dir)
      if not parent or parent == dir then break end
      table.insert(parts, 1, vim.fs.basename(dir))
      local s = vim.uv.fs_stat(parent)
      if s and s.ino == rs.ino and s.dev == rs.dev then return table.concat(parts, "/") end
      dir = parent
    end
  end
  return path
end

M.py_root_lines = {
  "from pathlib import Path",
  "",
  "ROOT = next((p for p in [Path.cwd(), *Path.cwd().parents]",
  "             if any((p / m).exists() for m in (\".here\", \".git\", \"DESCRIPTION\", \"pyproject.toml\")) or any(p.glob(\"*.Rproj\"))),",
  "            Path.cwd())  # here::here() と同じルート",
}

-- Python: バッファに無い import / ROOT を先頭に足す
local function py_prelude(buf, need_root)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local pre = {}
  if not text:match("import pandas as pd") then pre[#pre + 1] = "import pandas as pd" end
  if need_root and not text:match("\nROOT%s*=") and not text:match("^ROOT%s*=") then
    if #pre > 0 then pre[#pre + 1] = "" end
    vim.list_extend(pre, M.py_root_lines)
  end
  if #pre > 0 then pre[#pre + 1] = "" end
  return pre
end

local function insert(where, lang, lines, need_root)
  if lang == "python" then lines = vim.list_extend(py_prelude(where.buf, need_root), lines) end
  A().insert_code(where, lang, lines)
end

-- ---------------------------------------------------------------------------
-- 19. 型変換コード
-- ---------------------------------------------------------------------------
M.convert_kinds = {
  r = {
    { id = "factor", label = "factor(因子)" },
    { id = "factor_lv", label = "factor(水準の順番を指定)", levels = true },
    { id = "ordered", label = "ordered(順序因子・水準指定)", levels = true },
    { id = "numeric", label = "numeric(数値。文字/因子からも安全に)" },
    { id = "integer", label = "integer" },
    { id = "character", label = "character(文字列)" },
    { id = "logical", label = "logical(TRUE/FALSE)" },
    { id = "date", label = "Date(2024-01-31, 2024/1/31 など ymd)" },
    { id = "datetime", label = "日時 POSIXct(ymd_hms)" },
    { id = "excel_date", label = "Excel のシリアル値(45000 等)→ Date" },
  },
  python = {
    { id = "factor", label = "category" },
    { id = "factor_lv", label = "category(水準の順番を指定)", levels = true },
    { id = "ordered", label = "ordered category(順序・水準指定)", levels = true },
    { id = "numeric", label = "数値 pd.to_numeric(変換不能は NaN)" },
    { id = "integer", label = "Int64(欠損OKの整数)" },
    { id = "character", label = "string" },
    { id = "logical", label = "boolean" },
    { id = "date", label = "datetime pd.to_datetime(変換不能は NaT)" },
    { id = "datetime", label = "datetime(書式指定 format=)" },
    { id = "excel_date", label = "Excel のシリアル値(45000 等)→ datetime" },
  },
}

local r_fn = {
  factor = "factor",
  numeric = "\\(x) as.numeric(as.character(x))",
  integer = "\\(x) as.integer(as.character(x))",
  character = "as.character",
  logical = "as.logical",
  date = "lubridate::ymd",
  datetime = "lubridate::ymd_hms",
  excel_date = '\\(x) as.Date(as.numeric(as.character(x)), origin = "1899-12-30")',
}
local py_expr = {
  factor = '%s.astype("category")',
  numeric = '%s.apply(pd.to_numeric, errors="coerce")',
  integer = '%s.apply(pd.to_numeric, errors="coerce").astype("Int64")',
  character = '%s.astype("string")',
  logical = '%s.astype("boolean")',
  date = '%s.apply(pd.to_datetime, errors="coerce")',
  datetime = '%s.apply(pd.to_datetime, format="%%Y-%%m-%%d %%H:%%M:%%S", errors="coerce")',
  excel_date = '%s.apply(lambda s: pd.to_datetime(pd.to_numeric(s, errors="coerce"), unit="D", origin="1899-12-30"))',
}

local function lit(lang, v, numeric)
  if numeric then return tostring(v) end
  return q(v)
end

-- levels: { [col] = { values = {...}, numeric = bool } }
function M.gen_convert(lang, df, cols, kind, levels)
  local F = A().format_cols
  if lang == "r" then
    if kind == "factor_lv" or kind == "ordered" then
      local parts = {}
      for _, c in ipairs(cols) do
        local lv = levels[c]
        local vals = vim.tbl_map(function(v) return lit(lang, v, lv.numeric) end, lv.values)
        local nm = F("r", { c })
        parts[#parts + 1] = ("    %s = factor(%s, levels = c(%s)%s)"):format(nm, nm, table.concat(vals, ", "),
          kind == "ordered" and ", ordered = TRUE" or "") .. (#parts + 1 < #cols and "," or "")
      end
      return vim.list_extend(vim.list_extend({ ("%s <- %s |>"):format(df, df), "  dplyr::mutate(" }, parts), { "  )" })
    end
    return { ("%s <- %s |>"):format(df, df),
      ("  dplyr::mutate(dplyr::across(%s, %s))"):format(F("r", cols), r_fn[kind]) }
  end
  -- python
  if kind == "factor_lv" or kind == "ordered" then
    local out = {}
    for _, c in ipairs(cols) do
      local lv = levels[c]
      local vals = vim.tbl_map(function(v) return lit(lang, v, lv.numeric) end, lv.values)
      out[#out + 1] = ("%s[%s] = pd.Categorical(%s[%s], categories=[%s]%s)"):format(df, q(c), df, q(c),
        table.concat(vals, ", "), kind == "ordered" and ", ordered=True" or "")
    end
    return out
  end
  local sel = ("%s[%s]"):format(df, F("python", cols, true))
  return { ("%s = %s"):format(sel, py_expr[kind]:format(sel)) }
end

function M.convert()
  local where = A().capture_pos()
  local lang = A().lang()
  A().pick_df(lang, function(df)
    A().pick_columns(lang, df, function(cols)
      if #cols == 0 then return end
      local items = vim.tbl_map(function(k) return { text = k.label, label = k.label, kind = k } end, M.convert_kinds[lang])
      A().picker({ title = "変換先の型 (" .. #cols .. "列)", items = items, layout = "select", on_pick = function(sel)
        local kind = sel[1].kind
        if not kind.levels then
          return insert(where, lang, M.gen_convert(lang, df.name, cols, kind.id))
        end
        -- 水準をカーネルから取得(列ごとに順番に)
        local levels, i = {}, 0
        local function next_col()
          i = i + 1
          if i > #cols then
            insert(where, lang, M.gen_convert(lang, df.name, cols, kind.id, levels))
            return notify("水準は並び替えて使う(既定はソート順)")
          end
          local c = cols[i]
          A().query(lang, function(path)
            return (lang == "r" and ".nv$levels(%s, %s, %s)" or "_nv.levels(%s, %s, %s)"):format(q(df.name), q(c), path)
          end, function(res)
            local vals = type(res.values) == "table" and res.values or { res.values }
            if (res.n or 0) > #vals then notify(("%s: 水準 %d 個 → 先頭 %d 個のみ"):format(c, res.n, #vals), vim.log.levels.WARN) end
            levels[c] = { values = vals, numeric = res.numeric }
            next_col()
          end)
        end
        next_col()
      end })
    end, { title = "変換する列" })
  end)
end

-- ---------------------------------------------------------------------------
-- 38. カーソル下の表 → Word(docx)
-- ---------------------------------------------------------------------------
function M.docx()
  local lang = A().lang()
  local name = A().word()
  if not name or name == "" then return notify("カーソルを表オブジェクト名の上に", vim.log.levels.WARN) end
  local cur = vim.api.nvim_buf_get_name(0)
  local dir = cur ~= "" and vim.fn.fnamemodify(cur, ":h") or vim.fn.getcwd()
  local default = dir .. "/output/" .. name:gsub("[^%w_%-]", "_") .. ".docx"
  vim.ui.input({ prompt = "保存先 docx: ", default = default, completion = "file" }, function(file)
    if not file or file == "" then return end
    file = vim.fn.fnamemodify(vim.fn.expand(file), ":p")
    A().query(lang, function(path)
      return (lang == "r" and ".nv$docx(%s, %s, %s)" or "_nv.docx(%s, %s, %s)"):format(q(name), q(file), path)
    end, function(res)
      notify(("%s → %s"):format(name, res.text))
    end, { timeout = 60000 })
  end)
end

-- ---------------------------------------------------------------------------
-- 40. 相互参照ピッカー(@fig- @tbl- @sec- @eq- …)
-- ---------------------------------------------------------------------------
local ref_prefix = { "fig", "tbl", "sec", "eq", "lst", "thm", "lem", "cor", "prp", "def", "exm", "exr", "nte", "tip", "wrn", "imp", "cau" }
local ref_set = {}
for _, p in ipairs(ref_prefix) do ref_set[p] = true end
local skip_dirs = { [".git"] = true, [".venv"] = true, renv = true, node_modules = true, _site = true, _freeze = true,
  _targets = true, [".quarto"] = true, output = true }

-- lines から相互参照ラベルを抜き出す
function M.scan_refs(lines, file)
  local out, in_chunk, pending = {}, false, nil
  local function add(label, lnum, detail)
    local kind = label:match("^(%a+)%-")
    if kind and ref_set[kind] then
      out[#out + 1] = { label = label, kind = kind, file = file, lnum = lnum, detail = detail }
      return out[#out]
    end
  end
  for i, l in ipairs(lines) do
    if l:match("^%s*```+%s*{") then
      in_chunk, pending = true, nil
    elseif in_chunk and l:match("^%s*```+%s*$") then
      in_chunk, pending = false, nil
    elseif in_chunk then
      local lab = l:match("^%s*#|%s*label:%s*[\"']?([%w_%-]+)")
      if lab then pending = add(lab, i) end
      local cap = l:match("^%s*#|%s*%a+%-cap:%s*(.+)")
      if cap and pending then pending.detail = (cap:gsub("^[\"'|>]%s*", ""):gsub("[\"']%s*$", "")) end
    else
      for lab in l:gmatch("{#([%w_%-]+)") do
        local detail = l:match("^#+%s+(.-)%s*{") or l:match("^!%[(.-)%]") or l:match("^%s*:::") and "div" or nil
        add(lab, i, detail)
      end
    end
  end
  return out
end

function M.ref_root(file)
  for dir in vim.fs.parents(file) do
    if vim.uv.fs_stat(dir .. "/_quarto.yml") then return dir end
  end
  return vim.fn.fnamemodify(file, ":h")
end

function M.collect_refs(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local cur = vim.api.nvim_buf_get_name(buf)
  local root = cur ~= "" and M.ref_root(cur) or vim.fn.getcwd()
  local refs = {}
  vim.list_extend(refs, M.scan_refs(vim.api.nvim_buf_get_lines(buf, 0, -1, false), cur))
  local n = 0
  for name, type in vim.fs.dir(root, { depth = 4, skip = function(d) return not skip_dirs[d] end }) do
    if type == "file" and (name:match("%.qmd$") or name:match("%.Rmd$")) then
      local path = root .. "/" .. name
      if vim.fs.normalize(path) ~= vim.fs.normalize(cur) then
        n = n + 1
        if n > 300 then break end
        local ok, lines = pcall(vim.fn.readfile, path)
        if ok then vim.list_extend(refs, M.scan_refs(lines, path)) end
      end
    end
  end
  return refs, root
end

function M.crossref()
  local where = A().capture_pos()
  local refs, root = M.collect_refs(where.buf)
  if #refs == 0 then return notify("ラベル(#| label: fig-… / {#sec-…})が見つからない", vim.log.levels.WARN) end
  local seen, items = {}, {}
  for _, r in ipairs(refs) do
    if not seen[r.label] then
      seen[r.label] = true
      items[#items + 1] = {
        text = r.label .. " " .. (r.detail or ""), label = "@" .. r.label,
        detail = (r.detail and (r.detail .. "  ") or "") .. relpath(root, r.file) .. ":" .. r.lnum,
        file = r.file, pos = { r.lnum, 0 }, ref = r.label,
      }
    end
  end
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    return vim.ui.select(items, { prompt = "相互参照", format_item = function(it) return it.label .. "  " .. it.detail end },
      function(it) if it then A().insert_at(where, "@" .. it.ref) end end)
  end
  Snacks.picker.pick({
    title = "相互参照  Tab=複数(; 区切り)",
    items = items,
    format = function(item)
      return { { item.label, "SnacksPickerLabel" }, { "  " .. item.detail, "Comment" } }
    end,
    preview = "file",
    matcher = { sort_empty = false },
    layout = { preset = "default" },
    confirm = function(p, item)
      local sel = p:selected({ fallback = true })
      p:close()
      if #sel == 0 and item then sel = { item } end
      if #sel == 0 then return end
      local labels = vim.tbl_map(function(it) return "@" .. it.ref end, sel)
      vim.schedule(function() A().insert_at(where, table.concat(labels, "; ")) end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- 50. ファイル → 読込コード
-- ---------------------------------------------------------------------------
M.data_exts = { "csv", "tsv", "txt", "xlsx", "xlsm", "xls", "sav", "dta", "sas7bdat", "parquet", "feather", "arrow", "rds", "RData", "rda", "json" }

-- 先頭 64KB で文字コード判定: utf-8 / utf-8-bom / utf-16 / cp932
function M.detect_encoding(path)
  local f = io.open(path, "rb")
  if not f then return "utf-8" end
  local s = f:read(65536) or ""
  f:close()
  if s:sub(1, 3) == "\239\187\191" then return "utf-8-bom" end
  if s:sub(1, 2) == "\255\254" or s:sub(1, 2) == "\254\255" then return "utf-16" end
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
      or (c >= 0xF0 and c <= 0xF4) and 4 or 0
    if len == 0 then return "cp932" end
    if i + len - 1 > n then break end -- 64KB 境界で切れた文字
    for j = i + 1, i + len - 1 do
      local b = s:byte(j)
      if b < 0x80 or b > 0xBF then return "cp932" end
    end
    i = i + len
  end
  return "utf-8"
end

-- 区切り文字(先頭行のタブ/カンマ/セミコロンの数)
function M.detect_delim(path)
  local f = io.open(path, "rb")
  if not f then return "," end
  local line = f:read("*l") or ""
  f:close()
  local counts = { ["\t"] = select(2, line:gsub("\t", "")), [","] = select(2, line:gsub(",", "")), [";"] = select(2, line:gsub(";", "")) }
  local best, n = ",", -1
  for d, c in pairs(counts) do
    if c > n or (c == n and d == ",") then best, n = d, c end
  end
  return n > 0 and best or ","
end

-- xlsx のシート名(zip 内 workbook.xml を python3 で読む)
function M.excel_sheets(path)
  if not path:lower():match("%.xls[xm]$") then return {} end
  local py = vim.g.python3_host_prog or "python3"
  if vim.fn.executable(py) == 0 then py = "python3" end
  local code = [[
import html, re, sys, zipfile
x = zipfile.ZipFile(sys.argv[1]).read("xl/workbook.xml").decode("utf-8")
for m in re.finditer(r"<(?:\w+:)?sheet\b[^>]*?\bname=\"([^\"]*)\"", x):
    print(html.unescape(m.group(1)))
]]
  local ok, res = pcall(function() return vim.system({ py, "-c", code, path }, { text = true }):wait(5000) end)
  if not ok or res.code ~= 0 then return {} end
  return vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
end

function M.var_name(path)
  local stem = vim.fn.fnamemodify(path, ":t:r"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if stem == "" or not stem:match("%a") then return "df" end
  if stem:match("^%d") then stem = "d_" .. stem end
  return stem
end

-- 読込コード。opts: { root, sheet, enc, delim, var }
function M.gen_read(lang, path, opts)
  opts = opts or {}
  local rel = relpath(opts.root or M.root(path), path)
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  local var = opts.var or M.var_name(path)
  local enc = opts.enc
  local delim = opts.delim
  local is_text = ext == "csv" or ext == "tsv" or ext == "txt"
  if is_text then
    enc = enc or M.detect_encoding(path)
    delim = delim or (ext == "tsv" and "\t" or M.detect_delim(path))
  end
  if lang == "r" then
    local p = ("here::here(%s)"):format(q(rel))
    if is_text then
      local args = { p }
      local fn = delim == "\t" and "readr::read_tsv" or delim == ";" and "readr::read_csv2" or "readr::read_csv"
      local renc = ({ cp932 = "CP932", ["utf-16"] = "UTF-16" })[enc]
      if renc then args[#args + 1] = ("locale = readr::locale(encoding = %s)"):format(q(renc)) end
      args[#args + 1] = 'na = c("", "NA", "-", "#N/A")'
      return { ("%s <- %s(%s)"):format(var, fn, table.concat(args, ", ")) }
    end
    if ext == "xlsx" or ext == "xlsm" or ext == "xls" then
      local sheet = opts.sheet and q(opts.sheet) or "1"
      return { ("%s <- readxl::read_excel(%s, sheet = %s)  # skip = 行数, range = \"A1:F100\""):format(var, p, sheet) }
    end
    local fn = ({ sav = "haven::read_sav", dta = "haven::read_dta", sas7bdat = "haven::read_sas",
      parquet = "arrow::read_parquet", feather = "arrow::read_feather", arrow = "arrow::read_feather",
      rds = "readRDS", json = "jsonlite::fromJSON" })[ext]
    if ext == "rdata" or ext == "rda" then return { ("load(%s)  # 中のオブジェクトが復元される"):format(p) } end
    local lines = { ("%s <- %s(%s)"):format(var, fn or "rio::import", p) }
    if ext == "sav" or ext == "dta" then lines[#lines + 1] = ("%s <- haven::as_factor(%s)  # 値ラベル → factor"):format(var, var) end
    return lines
  end
  -- python
  local p = ("ROOT / %s"):format(q(rel))
  if is_text then
    local args = { p }
    if delim ~= "," then args[#args + 1] = ("sep=%s"):format(delim == "\t" and '"\\t"' or q(delim)) end
    local penc = ({ cp932 = "cp932", ["utf-8-bom"] = "utf-8-sig", ["utf-16"] = "utf-16" })[enc]
    if penc then args[#args + 1] = ("encoding=%s"):format(q(penc)) end
    args[#args + 1] = 'thousands=","'
    args[#args + 1] = 'na_values=["-", "#N/A"]'
    return { ("%s = pd.read_csv(%s)"):format(var, table.concat(args, ", ")) }
  end
  if ext == "xlsx" or ext == "xlsm" or ext == "xls" then
    local sheet = opts.sheet and q(opts.sheet) or "0"
    return { ("%s = pd.read_excel(%s, sheet_name=%s)  # skiprows=行数, usecols=\"A:F\""):format(var, p, sheet) }
  end
  if ext == "rds" then return { "import pyreadr  # uv pip install pyreadr", "", ("%s = pyreadr.read_r(%s)[None]"):format(var, p) } end
  if ext == "rdata" or ext == "rda" then return { "import pyreadr  # uv pip install pyreadr", "", ("%s = pyreadr.read_r(%s)  # dict: 名前 → DataFrame"):format(var, p) } end
  local fn = ({ sav = "pd.read_spss", dta = "pd.read_stata", sas7bdat = "pd.read_sas", parquet = "pd.read_parquet",
    feather = "pd.read_feather", arrow = "pd.read_feather", json = "pd.read_json" })[ext] or "pd.read_csv"
  local lines = { ("%s = %s(%s)"):format(var, fn, p) }
  if ext == "sav" then lines[1] = lines[1] .. "  # pyreadstat が必要" end
  return lines
end

local function read_file_code(where, lang, path)
  local root = M.root(vim.api.nvim_buf_get_name(where.buf))
  local function done(sheet)
    local lines = M.gen_read(lang, path, { root = root, sheet = sheet })
    insert(where, lang, lines, true)
    local enc = M.detect_encoding(path)
    if path:lower():match("%.[ct]sv$") or path:lower():match("%.txt$") then
      notify(("文字コード: %s / 区切り: %s"):format(enc, ({ ["\t"] = "タブ", [","] = "カンマ", [";"] = ";" })[M.detect_delim(path)]))
    end
  end
  local sheets = M.excel_sheets(path)
  if #sheets <= 1 then return done(sheets[1]) end
  local items = {}
  for i, s in ipairs(sheets) do items[i] = { text = s, label = s, detail = "シート" .. i } end
  A().picker({ title = "シート", items = items, layout = "select", on_pick = function(sel) done(sel[1].text) end })
end

function M.read_file()
  local where = A().capture_pos()
  local lang = A().lang()
  local root = M.root(vim.api.nvim_buf_get_name(where.buf))
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    return vim.ui.input({ prompt = "データファイル: ", default = root .. "/", completion = "file" }, function(p)
      if p and p ~= "" then read_file_code(where, lang, vim.fn.fnamemodify(vim.fn.expand(p), ":p")) end
    end)
  end
  Snacks.picker.files({
    title = "データファイル → 読込コード (" .. lang .. ")",
    cwd = root,
    ft = M.data_exts,
    hidden = false,
    ignored = true, -- data/ は .gitignore されていることが多い
    exclude = { ".venv", "renv", "node_modules", "_targets", "_freeze", "_site", ".git", ".quarto" },
    confirm = function(p, item)
      p:close()
      if not item then return end
      local path = item.file
      if not path:match("^/") then path = (item.cwd or root) .. "/" .. path end
      vim.schedule(function() read_file_code(where, lang, vim.fs.normalize(path)) end)
    end,
  })
end

-- ---------------------------------------------------------------------------
-- 51. Excel の範囲を貼り付け → df
-- ---------------------------------------------------------------------------
-- Excel のコピー(TSV。改行/タブを含むセルは "" で囲まれる)を行×列に
function M.parse_table(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local first = text:match("^[^\n]*") or ""
  local delim = first:find("\t") and "\t" or (first:find(",") and "," or "\t")
  local rows, row, field, inq = {}, {}, {}, false
  local i, n = 1, #text
  while i <= n do
    local ch = text:sub(i, i)
    if inq then
      if ch == '"' then
        if text:sub(i + 1, i + 1) == '"' then
          field[#field + 1] = '"'
          i = i + 1
        else
          inq = false
        end
      else
        field[#field + 1] = ch
      end
    elseif ch == '"' and #field == 0 then
      inq = true
    elseif ch == delim then
      row[#row + 1] = table.concat(field)
      field = {}
    elseif ch == "\n" then
      row[#row + 1] = table.concat(field)
      rows[#rows + 1] = row
      row, field = {}, {}
    else
      field[#field + 1] = ch
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 then
    row[#row + 1] = table.concat(field)
    rows[#rows + 1] = row
  end
  -- 空行除去・列数をそろえる・末尾の空列を落とす
  local out, ncol = {}, 0
  for _, r in ipairs(rows) do
    local nonempty = false
    for _, v in ipairs(r) do if vim.trim(v) ~= "" then nonempty = true end end
    if nonempty then
      out[#out + 1] = r
      ncol = math.max(ncol, #r)
    end
  end
  while ncol > 0 do
    local empty = true
    for _, r in ipairs(out) do if r[ncol] and vim.trim(r[ncol]) ~= "" then empty = false end end
    if not empty then break end
    ncol = ncol - 1
  end
  for _, r in ipairs(out) do
    for j = 1, ncol do r[j] = vim.trim(r[j] or "") end
    for j = #r, ncol + 1, -1 do r[j] = nil end
  end
  return out, ncol
end

local na_set = { [""] = true, NA = true, ["-"] = true, ["#N/A"] = true, ["N/A"] = true, ["#DIV/0!"] = true }

local function as_number(s)
  local t = s:gsub("^%+", "")
  if t:match("^%-?[%d,]+%.?%d*$") and (not t:find(",") or t:match("^%-?%d%d?%d?,%d%d%d")) then t = t:gsub(",", "") end
  if t:match("^%-?%d+%.?%d*$") or t:match("^%-?%.%d+$") or t:match("^%-?%d+%.?%d*[eE][%-+]?%d+$") then return t end
  return nil
end

-- rows[1] = 見出し。戻り値: { names, cols = { {values, numeric} } }
function M.table_spec(rows, ncol)
  local names, used = {}, {}
  for j = 1, ncol do
    local nm = rows[1][j] ~= "" and rows[1][j] or ("V" .. j)
    local base, k = nm, 2
    while used[nm] do
      nm = base .. "_" .. k
      k = k + 1
    end
    used[nm] = true
    names[j] = nm
  end
  local cols = {}
  for j = 1, ncol do
    local numeric, any = true, false
    for i = 2, #rows do
      local v = rows[i][j]
      if not na_set[v] then
        any = true
        if not as_number(v) then numeric = false end
      end
    end
    cols[j] = { numeric = numeric and any }
  end
  return names, cols
end

function M.gen_paste(lang, var, rows, ncol)
  local names, cols = M.table_spec(rows, ncol)
  local function cell(i, j)
    local v = rows[i][j]
    if na_set[v] then return lang == "r" and "NA" or "None" end
    if cols[j].numeric then return as_number(v) end
    return q(v)
  end
  if lang == "r" then
    local head = vim.tbl_map(function(nm) return "~" .. A().format_cols("r", { nm }) end, names)
    local lines = { var .. " <- tibble::tribble(", "  " .. table.concat(head, ", ") .. "," }
    for i = 2, #rows do
      local vals = {}
      for j = 1, ncol do vals[j] = cell(i, j) end
      lines[#lines + 1] = "  " .. table.concat(vals, ", ") .. (i < #rows and "," or "")
    end
    if #rows == 1 then lines[#lines] = lines[#lines]:gsub(",$", "") end
    lines[#lines + 1] = ")"
    return lines
  end
  local lines = { var .. " = pd.DataFrame({" }
  for j = 1, ncol do
    local vals = {}
    for i = 2, #rows do vals[#vals + 1] = cell(i, j) end
    lines[#lines + 1] = ("    %s: [%s],"):format(q(names[j]), table.concat(vals, ", "))
  end
  lines[#lines + 1] = "})"
  return lines
end

-- 行数が多いときは data/clip_<name>.tsv に保存して読込コードを返す
function M.write_tsv(rows, ncol, path)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local out = {}
  for _, r in ipairs(rows) do
    local vals = {}
    for j = 1, ncol do
      local v = (r[j] or ""):gsub("[\t\n]", " ")
      if v:find('"') then v = '"' .. v:gsub('"', '""') .. '"' end
      vals[j] = v
    end
    out[#out + 1] = table.concat(vals, "\t")
  end
  vim.fn.writefile(out, path)
end

M.inline_max_rows = 40

local function paste_finish(where, lang, text)
  local rows, ncol = M.parse_table(text)
  if #rows < 1 or ncol == 0 then return notify("表が空", vim.log.levels.WARN) end
  vim.ui.input({ prompt = ("変数名 (%d行×%d列, 1行目=列名): "):format(#rows - 1, ncol), default = "clip" }, function(var)
    if not var or var == "" then return end
    if #rows - 1 <= M.inline_max_rows then
      return insert(where, lang, M.gen_paste(lang, var, rows, ncol))
    end
    local root = M.root(vim.api.nvim_buf_get_name(where.buf))
    local path = root .. "/data/clip_" .. var .. ".tsv"
    M.write_tsv(rows, ncol, path)
    insert(where, lang, M.gen_read(lang, path, { root = root, var = var, enc = "utf-8", delim = "\t" }), true)
    notify(("%d 行 → %s に保存して読込コードを挿入"):format(#rows - 1, relpath(root, path)))
  end)
end

function M.paste_table()
  local where = A().capture_pos()
  local lang = A().lang()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].expandtab = false
  vim.api.nvim_buf_set_name(buf, "excel-paste://" .. buf)
  -- ローカル(SSH でない)でクリップボードが使えるなら最初から入れておく
  if vim.env.SSH_TTY == nil and vim.env.SSH_CONNECTION == nil and vim.fn.has("clipboard") == 1 then
    local ok, clip = pcall(vim.fn.getreg, "+")
    if ok and type(clip) == "string" and clip:find("\t") then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(clip:gsub("\r", ""), "\n", { plain = true }))
    end
  end
  local w = math.floor(vim.o.columns * 0.7)
  local h = math.floor(vim.o.lines * 0.6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h, row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    border = "rounded", title = " Excel の範囲を貼り付け(1行目=列名) → :w か <C-s> で確定 / q で中止 ", title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].list = true
  vim.wo[win].listchars = "tab:→ ,trail:·"
  local done = false
  local function confirm()
    if done then return end
    done = true
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    vim.bo[buf].modified = false
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    vim.schedule(function() paste_finish(where, lang, text) end)
  end
  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = confirm })
  vim.keymap.set({ "n", "i" }, "<C-s>", function() vim.cmd("stopinsert"); confirm() end, { buffer = buf })
  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  if vim.api.nvim_buf_line_count(buf) <= 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
    vim.cmd("startinsert")
    notify("ここに貼り付け(ターミナルの Ctrl+Shift+V / Cmd+V)")
  end
end

-- ---------------------------------------------------------------------------
-- \/ カーソルのあるチャンク(qmd)/セル(.py .R の # %%)の中身をまとめてコメント切替
-- ---------------------------------------------------------------------------
-- 対象範囲(1始まり, 両端含む)。フェンスと先頭の #| 行は除外
function M.cell_range(lines, row, ft)
  local s, e
  if ft == "quarto" or ft == "markdown" or ft == "rmd" then
    for i = row, 1, -1 do
      if lines[i]:match("^%s*```+%s*{") then s = i + 1 break end
      if lines[i]:match("^%s*```+%s*$") and i ~= row then return nil end
    end
    if not s then return nil end
    for j = s, #lines do
      if lines[j]:match("^%s*```+%s*$") then e = j - 1 break end
    end
    if not e or row > e + 1 then return nil end
    while s <= e and lines[s]:match("^%s*#|") do s = s + 1 end
  else
    s, e = 1, #lines
    for i = row, 1, -1 do
      if lines[i]:match("^%s*# %%%%") then s = i + 1 break end
    end
    for j = math.max(row, s), #lines do
      if lines[j]:match("^%s*# %%%%") and j >= s then e = j - 1 break end
    end
  end
  while e >= s and vim.trim(lines[e]) == "" do e = e - 1 end
  while s <= e and vim.trim(lines[s]) == "" do s = s + 1 end
  if s > e then return nil end
  return s, e
end

function M.toggle_cell_comment()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local s, e = M.cell_range(lines, row, vim.bo.filetype)
  if not s then return notify("チャンク/セルの中にカーソルを置く", vim.log.levels.WARN) end
  local ok, C = pcall(require, "vim._comment")
  if ok and C.toggle_lines then
    -- コメント記号はチャンクの言語に合わせる(treesitter の言語注入を参照する位置を渡す)
    local col = (lines[s]:find("%S") or 1) - 1
    C.toggle_lines(s, e, { s, col })
  else
    vim.cmd(("%d,%dnormal gcc"):format(s, e))
  end
end

-- ---------------------------------------------------------------------------
-- \? 自分のキー割り当て早見表(今のバッファで有効なものを実際の設定から集める)
-- ---------------------------------------------------------------------------
local key_groups = {
  a = "レシピ", d = "データ表示", h = "httpgd", i = "挿入", m = "molten", p = "peek", q = "quarto",
  r = "実行", t = "targets", v = "変数", y = "コピー/出力",
}
local extra_lhs = { "<S-CR>", "]x", "[x", "<M-c>", "<M-r>", "<C-M-s>", "<C-M-p>", "<C-M-r>" }
local mode_name = { n = "", i = "挿入", x = "選択", v = "選択" }

function M.collect_keys(buf)
  buf = buf or 0
  local ll = vim.g.maplocalleader or "\\"
  local extra = {}
  for _, k in ipairs(extra_lhs) do extra[vim.keycode(k)] = true end
  local seen, items = {}, {}
  for _, mode in ipairs({ "n", "x", "i" }) do
    local maps = vim.api.nvim_buf_get_keymap(buf, mode)
    vim.list_extend(maps, vim.api.nvim_get_keymap(mode))
    for _, m in ipairs(maps) do
      local lhs = m.lhs
      local raw = vim.keycode(lhs)
      local mine = lhs:sub(1, #ll) == ll or raw:sub(1, #ll) == ll or extra[raw]
      local key = mode .. raw
      if mine and m.desc and m.desc ~= "" and not lhs:match("<Plug>") and not seen[key] then
        seen[key] = true
        local shown = lhs:sub(1, #ll) == ll and ("\\" .. lhs:sub(#ll + 1)) or lhs
        local g = lhs:sub(1, #ll) == ll and key_groups[lhs:sub(#ll + 1, #ll + 1)] or nil
        items[#items + 1] = { lhs = lhs, shown = shown, mode = mode, desc = m.desc, group = g or "" }
      end
    end
  end
  table.sort(items, function(a, b)
    if a.shown ~= b.shown then return a.shown < b.shown end
    return a.mode < b.mode
  end)
  -- 自作コマンド
  local cmds = {}
  for name, c in pairs(vim.api.nvim_get_commands({})) do
    if name:match("^Q%u") or name:match("^Analysis") then
      cmds[#cmds + 1] = { cmd = name, desc = c.definition or "" }
    end
  end
  table.sort(cmds, function(a, b) return a.cmd < b.cmd end)
  return items, cmds
end

-- Markdown の早見表(ファイルに書き出す用)
function M.keys_markdown(items, cmds)
  local out = { "# キー割り当て早見表 (" .. vim.bo.filetype .. ")" }
  local order, by = {}, {}
  for _, it in ipairs(items) do
    local g = it.group ~= "" and it.group or "その他"
    if not by[g] then
      by[g] = {}
      order[#order + 1] = g
    end
    table.insert(by[g], it)
  end
  table.sort(order, function(a, b) return (a == "その他" and "\255" or a) < (b == "その他" and "\255" or b) end)
  for _, g in ipairs(order) do
    out[#out + 1] = ""
    out[#out + 1] = "## " .. g
    for _, it in ipairs(by[g]) do
      out[#out + 1] = ("- `%s`%s  %s"):format(it.shown, mode_name[it.mode] ~= "" and (" (" .. mode_name[it.mode] .. ")") or "", it.desc)
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = "## コマンド"
  for _, c in ipairs(cmds) do out[#out + 1] = ("- `:%s`  %s"):format(c.cmd, c.desc) end
  return out
end

function M.keys()
  local items, cmds = M.collect_keys(0)
  local src_win = vim.api.nvim_get_current_win()
  local list = {}
  for _, it in ipairs(items) do
    local m = mode_name[it.mode] ~= "" and ("[" .. mode_name[it.mode] .. "] ") or ""
    list[#list + 1] = {
      text = it.shown .. " " .. it.desc .. " " .. it.group, label = it.shown,
      detail = m .. it.desc .. (it.group ~= "" and ("  · " .. it.group) or ""), key = it,
      preview = { text = ("%s\n\nモード: %s\n%s"):format(it.shown, it.mode, it.desc), ft = "text" },
    }
  end
  for _, c in ipairs(cmds) do
    list[#list + 1] = { text = ":" .. c.cmd .. " " .. c.desc, label = ":" .. c.cmd, detail = c.desc, cmd = c.cmd,
      preview = { text = ":" .. c.cmd .. "\n\n" .. c.desc, ft = "text" } }
  end
  local md = M.keys_markdown(items, cmds)
  local ok, Snacks = pcall(require, "snacks")
  if not ok then return A().float(table.concat(md, "\n"), "キー割り当て", "markdown") end
  Snacks.picker.pick({
    title = "キー割り当て (" .. vim.bo.filetype .. ")  Enter=実行  <C-e>=早見表を開く",
    items = list,
    format = function(item)
      return { { ("%-14s"):format(item.label), "SnacksPickerLabel" }, { " " .. item.detail, "Comment" } }
    end,
    preview = "preview",
    matcher = { sort_empty = false },
    layout = { preset = "default" },
    confirm = function(p, item)
      p:close()
      if not item then return end
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(src_win) then vim.api.nvim_set_current_win(src_win) end
        if item.cmd then
          vim.api.nvim_feedkeys(":" .. item.cmd .. " ", "n", false)
        elseif item.key.mode == "n" then
          vim.cmd("stopinsert")
          vim.defer_fn(function() vim.api.nvim_feedkeys(vim.keycode(item.key.lhs), "m", false) end, 30)
        else
          notify(("%s は%sモードで押す"):format(item.key.shown, mode_name[item.key.mode]))
        end
      end)
    end,
    actions = {
      cheatsheet = function(p)
        p:close()
        vim.schedule(function() A().float(table.concat(md, "\n"), "キー割り当て早見表", "markdown") end)
      end,
    },
    win = { input = { keys = { ["<C-e>"] = { "cheatsheet", mode = { "n", "i" } } } } },
  })
end

return M
