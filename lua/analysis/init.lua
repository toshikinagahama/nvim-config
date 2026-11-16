-- 分析補助: 実行中の Jupyter カーネル(molten)と nvim の間で値をやり取りする機能群。
-- カーネル側ヘルパ: r/nvim_tools.R(.nv)、py/nvim_tools.py(_nv)。結果は一時 JSON ファイル経由で受け取る
-- (MoltenEvaluateArgument の出力はバッファに表示されないため)。
local M = {}

local config_dir = vim.fn.stdpath("config")
M.kernels = { python = "python3", r = "ir" }
M.last_df = {} -- 言語ごとに最後に選んだデータフレーム名
M.figviewer_port = 8766

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "analysis" })
end
M.notify = notify

-- ---------------------------------------------------------------------------
-- 言語・カーネル
-- ---------------------------------------------------------------------------

-- qmd: カーソルのあるチャンクの言語。チャンク外なら直前(無ければ最初)のチャンクの言語
function M.lang(buf, row)
  buf = buf or 0
  local ft = vim.bo[buf].filetype
  if ft == "python" then return "python" end
  if ft == "r" then return "r" end
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local function fence_lang(l)
    local lang = l:match("^%s*```+%s*{%s*([%w_]+)")
    return lang and lang:lower()
  end
  for i = row, 1, -1 do
    local lang = fence_lang(lines[i])
    if lang then return lang end
  end
  for _, l in ipairs(lines) do
    local lang = fence_lang(l)
    if lang then return lang end
  end
  return "r"
end

-- カーソルがチャンク内か(qmd)。返り値: inside, チャンク終端行
function M.chunk_at(row)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  row = row or vim.api.nvim_win_get_cursor(0)[1]
  for i = row, 1, -1 do
    if lines[i]:match("^%s*```+%s*{") then
      for j = i + 1, #lines do
        if lines[j]:match("^%s*```+%s*$") then return j >= row, j end
      end
      return true, #lines
    end
    if lines[i]:match("^%s*```+%s*$") and i ~= row then return false end
  end
  return false
end

-- このバッファで使えるカーネルID。別バッファで起動済みなら共有で接続、未起動なら nil
function M.kernel(lang, start)
  local k = M.kernels[lang]
  if not k then return nil end
  local ok, mine = pcall(vim.fn.MoltenRunningKernels, true)
  if not ok then
    notify("molten 未読込(qmd/.py/.R を開いてから)", vim.log.levels.WARN)
    return nil
  end
  if vim.tbl_contains(mine, k) then return k end
  local _, all = pcall(vim.fn.MoltenRunningKernels, false)
  if type(all) == "table" and vim.tbl_contains(all, k) then
    vim.cmd("MoltenInit shared " .. k)
    return k
  end
  if start then
    vim.cmd("MoltenInit " .. k)
    return k
  end
  notify(("%s カーネル未起動。先にセルを実行(\\r)"):format(k), vim.log.levels.WARN)
  return nil
end

-- R / Python の文字列リテラル
local function q(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end
M.q = q

local function helper_call(lang, call, force)
  if lang == "r" then
    local src = ("source(%s)"):format(q(config_dir .. "/r/nvim_tools.R"))
    local load = force and src or ('if (!"nvim_tools" %%in%% search()) %s'):format(src)
    return ("{%s; %s}"):format(load, call)
  end
  local load = ("exec(open(%s, encoding='utf-8').read())"):format(q(config_dir .. "/py/nvim_tools.py"))
  if not force then load = load .. ' if "_nv" not in globals() else None' end
  return load .. "; " .. call
end

-- カーネルでコードを実行(出力は捨てる)。1行で渡すこと
function M.eval(lang, code)
  local k = M.kernel(lang)
  if not k then return false end
  vim.cmd(("MoltenEvaluateArgument %s %s"):format(k, code))
  return true
end

-- ヘルパを呼んで JSON を受け取る。call は path(文字列リテラル)を受け取ってコードを返す関数
function M.query(lang, call, cb, opts)
  opts = opts or {}
  local path = vim.fn.tempname() .. ".json"
  local code = helper_call(lang, call(q(path)), opts.force)
  if not M.eval(lang, code) then return end
  local waited, timeout = 0, opts.timeout or 30000
  local timer = vim.uv.new_timer()
  local hint_shown = false
  timer:start(100, 100, vim.schedule_wrap(function()
    waited = waited + 100
    if vim.uv.fs_stat(path) then
      timer:stop()
      timer:close()
      local ok, data = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"), { luanil = { object = true, array = true } })
      end)
      vim.uv.fs_unlink(path)
      if not ok then return notify("結果の読込失敗: " .. tostring(data), vim.log.levels.ERROR) end
      if type(data) == "table" and data.error then
        return notify(data.error, vim.log.levels.ERROR)
      end
      cb(data)
    elseif waited >= timeout then
      timer:stop()
      timer:close()
      notify("カーネル応答なし(実行中のセル待ち?)。少し待って再実行", vim.log.levels.WARN)
    elseif waited == 3000 and not hint_shown then
      hint_shown = true
      notify("カーネル実行待ち…")
    end
  end))
end

-- ---------------------------------------------------------------------------
-- 表示・挿入の部品
-- ---------------------------------------------------------------------------

-- カーソル下の名前(R の a.b、日本語列名、`バッククォート` 内も可)。ビジュアル選択があればそれ
function M.word()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" then
    local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
    local text = vim.fn.getregion(s, e, { type = mode })
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    return vim.trim(table.concat(text, " "))
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  -- バッククォートで囲まれた中にいればその中身
  for s, inner, e in line:gmatch("()`([^`]+)`()") do
    if col >= s and col < e then return inner end
  end
  local chars = "[%w_%.\128-\255]"
  local s, e = col, col
  if not line:sub(col, col):match(chars) then return vim.fn.expand("<cword>") end
  while s > 1 and line:sub(s - 1, s - 1):match(chars) do s = s - 1 end
  while e < #line and line:sub(e + 1, e + 1):match(chars) do e = e + 1 end
  -- マルチバイト文字の途中で切れないよう調整
  while s > 1 and line:byte(s) >= 0x80 and line:byte(s) < 0xC0 do s = s - 1 end
  return (line:sub(s, e):gsub("^%.+", ""))
end

function M.float(text, title, ft)
  local lines = vim.split(text, "\n", { plain = true })
  local ok, Snacks = pcall(require, "snacks")
  if ok then
    Snacks.win({
      text = lines,
      title = title and (" " .. title .. " ") or nil,
      ft = ft or "text",
      width = 0.6,
      height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8)),
      border = "rounded",
      wo = { wrap = false, number = false, relativenumber = false },
      bo = { modifiable = false },
      keys = { q = "close", ["<Esc>"] = "close" },
    })
  else
    vim.lsp.util.open_floating_preview(lines, ft or "text", { border = "rounded", title = title })
  end
end

-- テキストを、ピッカーを開く前のカーソル位置に挿入(挿入モードから呼ばれたら挿入モードに戻す)
function M.capture_pos()
  return {
    win = vim.api.nvim_get_current_win(),
    buf = vim.api.nvim_get_current_buf(),
    pos = vim.api.nvim_win_get_cursor(0),
    insert = vim.fn.mode():sub(1, 1) == "i",
  }
end

function M.insert_at(where, text)
  if not vim.api.nvim_win_is_valid(where.win) then return end
  vim.api.nvim_set_current_win(where.win)
  local row, col = where.pos[1], where.pos[2]
  local line = vim.api.nvim_buf_get_lines(where.buf, row - 1, row, false)[1] or ""
  -- ノーマルモードではカーソル文字の後ろ(行が空なら先頭)に入れる
  if not where.insert and #line > 0 then
    col = col + #vim.fn.strcharpart(line:sub(col + 1), 0, 1)
  end
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(where.buf, row - 1, col, row - 1, col, lines)
  local end_row = row + #lines - 1
  local end_col = (#lines == 1 and col or 0) + #lines[#lines]
  vim.api.nvim_win_set_cursor(where.win, { end_row, end_col })
  if where.insert then
    vim.cmd("startinsert")
    vim.api.nvim_win_set_cursor(where.win, { end_row, end_col })
  end
end

-- 行単位で挿入。qmd でチャンク外なら ```{lang} で囲む
function M.insert_code(where, lang, code_lines)
  vim.api.nvim_set_current_win(where.win)
  vim.cmd("stopinsert")
  local row = where.pos[1]
  local lines = code_lines
  if vim.bo[where.buf].filetype == "quarto" or vim.bo[where.buf].filetype == "markdown" then
    local inside = M.chunk_at(row)
    if not inside then
      lines = vim.list_extend({ "", "```{" .. lang .. "}" }, vim.list_extend(vim.deepcopy(code_lines), { "```", "" }))
    end
  end
  vim.api.nvim_buf_set_lines(where.buf, row, row, false, lines)
  vim.api.nvim_win_set_cursor(where.win, { row + 1, 0 })
end

-- R/Python 向けの列名表記
function M.format_cols(lang, cols, force_vector)
  local function r_name(c)
    if c:match("^[%a][%w._]*$") or c:match("^%.[%a_][%w._]*$") then return c end
    return "`" .. c:gsub("`", "\\`") .. "`"
  end
  if #cols == 1 and not force_vector then
    return lang == "python" and q(cols[1]) or r_name(cols[1])
  end
  local quoted = vim.tbl_map(q, cols)
  if lang == "python" then return "[" .. table.concat(quoted, ", ") .. "]" end
  return "c(" .. table.concat(quoted, ", ") .. ")"
end

-- ---------------------------------------------------------------------------
-- ピッカー(snacks.nvim)
-- ---------------------------------------------------------------------------

local function picker(opts)
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    -- snacks が無ければ vim.ui.select(単一選択のみ)
    return vim.ui.select(opts.items, {
      prompt = opts.title,
      format_item = function(it) return it.text end,
    }, function(item)
      if item then opts.on_pick({ item }) end
    end)
  end
  Snacks.picker.pick({
    title = opts.title,
    items = opts.items,
    format = function(item)
      local ret = { { item.label or item.text, "SnacksPickerLabel" } }
      if item.detail then
        ret[#ret + 1] = { "  " .. item.detail, "Comment" }
      end
      return ret
    end,
    preview = "preview",
    layout = { preset = opts.layout or "default" },
    confirm = function(p, item)
      local sel = p:selected({ fallback = true })
      p:close()
      if #sel > 0 or item then
        vim.schedule(function() opts.on_pick(#sel > 0 and sel or { item }) end)
      end
    end,
    actions = opts.actions,
    win = opts.keys and { input = { keys = opts.keys }, list = { keys = opts.keys } } or nil,
  })
end
M.picker = picker

-- データフレーム一覧を取って 1つ選ぶ(1つしか無い/カーソル下がDFならそれ)
function M.pick_df(lang, cb, opts)
  opts = opts or {}
  M.query(lang, function(path) return (lang == "r" and ".nv$dfs(%s)" or "_nv.dfs(%s)"):format(path) end, function(dfs)
    if #dfs == 0 then return notify("データフレームがカーネルに無い", vim.log.levels.WARN) end
    local by_name = {}
    for _, d in ipairs(dfs) do by_name[d.name] = d end
    if opts.prefer and by_name[opts.prefer] then return cb(by_name[opts.prefer]) end
    if #dfs == 1 then return cb(dfs[1]) end
    local items = {}
    for _, d in ipairs(dfs) do
      local cols = vim.tbl_map(function(c) return c.name end, d.columns)
      items[#items + 1] = {
        text = d.name, label = d.name, detail = d.shape, df = d,
        preview = { text = table.concat(cols, "\n"), ft = "text" },
      }
    end
    -- 前回選んだものを先頭に
    table.sort(items, function(a, b)
      return (a.text == M.last_df[lang] and 0 or 1) < (b.text == M.last_df[lang] and 0 or 1)
    end)
    M.picker({ title = opts.title or "データフレーム", items = items, layout = "select",
      on_pick = function(sel) cb(sel[1].df) end })
  end)
end

-- 列を選ぶ(Tab で複数選択)。cb(列名リスト)
function M.pick_columns(lang, df, cb, opts)
  opts = opts or {}
  M.last_df[lang] = df.name
  local items = {}
  for _, c in ipairs(df.columns) do
    items[#items + 1] = {
      text = c.name, label = c.name,
      detail = ("%s  NA=%s  uniq=%s"):format(c.type, c.na, c.unique),
      preview = { text = c.preview or "", ft = "text" },
    }
  end
  M.picker({
    title = (opts.title or "列") .. " [" .. df.name .. "]" .. (opts.single and "" or "  Tab=複数選択"),
    items = items,
    on_pick = function(sel)
      cb(vim.tbl_map(function(it) return it.text end, sel))
    end,
  })
end

-- ---------------------------------------------------------------------------
-- 機能
-- ---------------------------------------------------------------------------

-- 9. 列名ピッカー: 選んだ列名を挿入
function M.columns()
  local where = M.capture_pos()
  local lang = M.lang()
  local word = M.word()
  M.pick_df(lang, function(df)
    M.pick_columns(lang, df, function(cols)
      M.insert_at(where, M.format_cols(lang, cols))
    end)
  end, { prefer = word })
end

-- 2. 変数一覧(Enter=名前を挿入、<C-v>=figviewerで表示)
function M.objects()
  local where = M.capture_pos()
  local lang = M.lang()
  M.query(lang, function(path) return (lang == "r" and ".nv$objects(%s)" or "_nv.objects(%s)"):format(path) end, function(objs)
    if #objs == 0 then return notify("変数なし") end
    local items = {}
    for _, o in ipairs(objs) do
      items[#items + 1] = {
        text = o.name, label = o.name,
        detail = ("%s  %s  %s"):format(o.class, o.shape, o.size or ""),
        preview = { text = o.preview or "", ft = "text" },
      }
    end
    M.picker({
      title = ("変数 (%s)  Enter=挿入  <C-v>=表で見る"):format(M.kernels[lang]),
      items = items,
      on_pick = function(sel)
        M.insert_at(where, table.concat(vim.tbl_map(function(it) return it.text end, sel), ", "))
      end,
      actions = {
        view_table = function(p, item)
          p:close()
          vim.schedule(function() M.view(lang, item.text) end)
        end,
      },
      keys = { ["<C-v>"] = { "view_table", mode = { "n", "i" } } },
    })
  end)
end

-- figviewer サーバ(Python カーネルが無くても R の表を見られるよう単独起動)
local function ensure_figviewer(cb)
  local tcp = vim.uv.new_tcp()
  tcp:connect("127.0.0.1", M.figviewer_port, function(err)
    tcp:close()
    vim.schedule(function()
      if not err then return cb() end
      local script = (vim.env.IPYTHONDIR or vim.fn.expand("~/.ipython")) .. "/profile_default/startup/10-figviewer.py"
      if vim.fn.filereadable(script) == 0 then
        return notify("figviewer が無い: " .. script, vim.log.levels.ERROR)
      end
      local py = vim.g.python3_host_prog or "python3"
      vim.fn.jobstart({ py, script }, {
        detach = true,
        env = { FIGVIEWER_SERVE = "1", FIGVIEWER_PORT = tostring(M.figviewer_port) },
      })
      vim.defer_fn(cb, 500)
    end)
  end)
end

-- 1. カーソル下(無ければ選択)の表を figviewer(http://localhost:8766)で見る
function M.view(lang, name)
  lang = lang or M.lang()
  local function send(n)
    ensure_figviewer(function()
      M.query(lang, function(path)
        return (lang == "r" and ".nv$view(%s, %s)" or "_nv.view(%s, %s)"):format(q(n), path)
      end, function(res) notify(res.text) end)
    end)
  end
  name = name or M.word()
  if name and name ~= "" then return send(name) end
  M.pick_df(lang, function(df) send(df.name) end)
end

-- 12. カーソル下の変数/列をその場で確認(kind = summary / table / hist)
function M.peek(kind)
  local lang = M.lang()
  local name = M.word()
  if not name or name == "" then return notify("カーソルを変数名/列名の上に", vim.log.levels.WARN) end
  local df = M.last_df[lang] or "df"
  local prefix = ""
  if kind == "hist" and lang == "r" then
    prefix = ("source(%s); "):format(q(config_dir .. "/r/httpgd.R"))
  end
  M.query(lang, function(path)
    if lang == "r" then
      return prefix .. (".nv$peek(%s, %s, %s, %s)"):format(q(name), q(kind), q(df), path)
    end
    return ("_nv.peek(%s, %s, %s, %s)"):format(q(name), q(kind), q(df), path)
  end, function(res)
    if kind == "hist" then return notify(res.text) end
    M.float(res.text, name .. " · " .. kind)
  end)
end

-- 16. カーソル下の表を Excel 貼付用 TSV でクリップボードへ
function M.yank_table()
  local lang = M.lang()
  local name = M.word()
  if not name or name == "" then return notify("カーソルを表オブジェクト名の上に", vim.log.levels.WARN) end
  M.query(lang, function(path)
    return (lang == "r" and ".nv$tsv(%s, %s)" or "_nv.tsv(%s, %s)"):format(q(name), path)
  end, function(res)
    vim.fn.setreg("+", res.text)
    vim.fn.setreg('"', res.text)
    notify(("%s (%s) を TSV でコピー → Excel に貼付"):format(name, res.shape or ""))
  end)
end

-- 2'. ヘルパの読み直し(nvim_tools を編集したとき)
function M.reload()
  local lang = M.lang()
  M.query(lang, function(path)
    return (lang == "r" and ".nv$out(list(ok = TRUE), %s)" or '_nv.out({"ok": True}, %s)'):format(path)
  end, function() notify("nvim_tools 再読込") end, { force = true })
end

-- ---------------------------------------------------------------------------
-- 15. アウトライン(見出し・チャンク)
-- ---------------------------------------------------------------------------
function M.outline()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local items, in_chunk, chunk = {}, false, nil
  local ft = vim.bo.filetype
  for i, l in ipairs(lines) do
    if ft == "quarto" or ft == "markdown" then
      local lang = l:match("^%s*```+%s*{%s*([%w_]+)")
      if lang then
        in_chunk = true
        chunk = { lnum = i, lang = lang, label = l:match("{%s*[%w_]+[%s,]+([^}=]+)}") }
        items[#items + 1] = chunk
      elseif in_chunk and l:match("^%s*```+%s*$") then
        in_chunk = false
      elseif in_chunk then
        local label = l:match("^#|%s*label:%s*(%S+)")
        if label then chunk.label = label end
        local cap = l:match("^#|%s*[ft][ib][gl]%-cap:%s*\"?([^\"]+)")
        if cap then chunk.cap = cap end
      else
        local hashes, title = l:match("^(#+)%s+(.+)")
        if hashes then items[#items + 1] = { lnum = i, level = #hashes, title = title } end
        local inc = l:match("{{<%s*include%s+(%S+)%s*>}}")
        if inc and not l:match("^%s*<!%-%-") then items[#items + 1] = { lnum = i, include = inc } end
      end
    else
      -- .py / .R: # %% セルと # 見出し
      local cell = l:match("^%s*# %%%%%s*(.*)")
      if cell then items[#items + 1] = { lnum = i, lang = "cell", label = cell ~= "" and cell or nil } end
      local sec = l:match("^#+%s+(.-)%s*%-%-%-%-+%s*$")
      if sec then items[#items + 1] = { lnum = i, level = 1, title = sec } end
    end
  end
  local level = 0
  local out = {}
  for _, it in ipairs(items) do
    local text
    if it.title then
      level = it.level
      text = string.rep("  ", it.level - 1) .. it.title
    elseif it.include then
      text = string.rep("  ", level) .. "📄 " .. it.include
    else
      text = string.rep("  ", level) .. ("▸ {%s} %s"):format(it.lang, it.label or "") .. (it.cap and ("  " .. it.cap) or "")
    end
    out[#out + 1] = { text = text, label = text, detail = tostring(it.lnum), file = vim.api.nvim_buf_get_name(buf), pos = { it.lnum, 0 }, buf = buf }
  end
  local ok, Snacks = pcall(require, "snacks")
  if not ok then return notify("snacks.nvim が必要", vim.log.levels.ERROR) end
  Snacks.picker.pick({
    title = "アウトライン",
    items = out,
    format = function(item) return { { item.text } } end,
    preview = "file",
    sort = { fields = { "idx" } },
    matcher = { sort_empty = false },
    confirm = "jump",
  })
end

-- ---------------------------------------------------------------------------
-- 14. ステータスライン: 起動中カーネルと実行中セル数
-- ---------------------------------------------------------------------------
local status_cache = { t = 0, text = "" }
function M.statusline()
  local now = vim.uv.now()
  if now - status_cache.t < 500 then return status_cache.text end
  status_cache.t = now
  local ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
  if not ok or type(kernels) ~= "table" or #kernels == 0 then
    status_cache.text = ""
    return ""
  end
  -- molten の出力見出し(virt text)から実行中/待機中を数える
  local running, queued = 0, 0
  local ns = vim.api.nvim_get_namespaces()
  for name, id in pairs(ns) do
    if name:lower():find("molten") then
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, id, 0, -1, { details = true })) do
        local d = m[4]
        local chunks = {}
        for _, vl in ipairs(d.virt_lines or {}) do vim.list_extend(chunks, vl) end
        vim.list_extend(chunks, d.virt_text or {})
        for _, c in ipairs(chunks) do
          local t = c[1] or ""
          if t:find("Running", 1, true) then running = running + 1 end
          if t:find("On Hold", 1, true) then queued = queued + 1 end
        end
      end
    end
  end
  local state = running > 0 and (" ⏳" .. (queued > 0 and ("+" .. queued) or "")) or " ✓"
  status_cache.text = "󰠮 " .. table.concat(kernels, ",") .. state
  return status_cache.text
end

return M
