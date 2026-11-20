-- Quarto まわり: preview / render、パーツ単体 render、エラー行ジャンプ、パーツ新規作成、
-- テンプレート(scss等)コピー、targets、スニペットピッカー
local A = require("analysis")
local M = {}

local config_dir = vim.fn.stdpath("config")
local preview_job = nil
M.last_term = nil -- 直近の preview/render のターミナルバッファ
M.last_file = nil -- 直近に preview/render したファイル
M.temp_files = {} -- パーツ単体 preview の一時 qmd(preview 停止・終了時に削除)

local function cleanup_temp()
  for _, f in ipairs(M.temp_files) do
    local stem = vim.fn.fnamemodify(f, ":r")
    vim.fn.delete(f)
    vim.fn.delete(stem .. ".html")
    vim.fn.delete(stem .. "_files", "rf")
    vim.fn.delete(stem .. "_cache", "rf")
  end
  M.temp_files = {}
end
M.cleanup_temp = cleanup_temp
vim.api.nvim_create_autocmd("VimLeavePre", { callback = cleanup_temp })

local INCLUDE = "{{<%s*include%s+(%S+)%s*>}}"

local function include_of(line)
  if line:match("^%s*<!%-%-") then return nil end
  return line:match(INCLUDE)
end

M.term_height = 10 -- preview/render ターミナルの高さ(固定)

local function open_term(cmd, file, on_exit)
  local source_win = vim.api.nvim_get_current_win()
  local old = M.last_term
  -- 前回のターミナル窓が見えていればそれを使い回す(下に窓が積み重ならないように)
  local win
  if old and vim.api.nvim_buf_is_valid(old) then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == old then win = w break end
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd("botright split")
    win = vim.api.nvim_get_current_win()
  end
  vim.cmd("enew")
  local job = vim.fn.jobstart(cmd, {
    term = true,
    cwd = vim.fn.fnamemodify(file, ":h"),
    env = { FIGVIEWER = "0" }, -- render の図が figviewer に吸われないように
    on_exit = on_exit,
  })
  vim.bo.bufhidden = "hide"
  vim.wo[win].winfixheight = true -- 他の窓の開閉で高さが変わらないように
  vim.api.nvim_win_set_height(win, M.term_height)
  M.last_term = vim.api.nvim_get_current_buf()
  M.last_file = file
  -- 前回のターミナルバッファは、もう終わっていれば片付ける(実行中の render は残す)
  if old and old ~= M.last_term and vim.api.nvim_buf_is_valid(old) then
    local ch = vim.bo[old].channel
    local running = ch and ch > 0 and vim.fn.jobwait({ ch }, 0)[1] == -1
    if not running then pcall(vim.api.nvim_buf_delete, old, { force = true }) end
  end
  vim.api.nvim_set_current_win(source_win)
  return job, M.last_term
end

-- ---------------------------------------------------------------------------
-- preview / render
-- ---------------------------------------------------------------------------
local function stop_job()
  if preview_job then
    pcall(vim.fn.jobstop, preview_job)
    preview_job = nil
  end
  vim.fn.system({ "pkill", "-u", vim.env.USER or "", "-f", "quarto.*preview.*--port 4200" })
end

-- \qq: preview 停止+パーツ単体 preview の一時ファイル削除
function M.stop()
  stop_job()
  cleanup_temp()
end

-- 開いているファイル(または file)だけを preview(ポート4200固定)
-- extra: 追加の引数(例 { "--cache" })
function M.preview(file, extra)
  if not file then
    file = vim.api.nvim_buf_get_name(0)
    if file == "" then return A.notify("ファイルを保存してから \\qp", vim.log.levels.WARN) end
    vim.cmd("silent! write")
  end
  stop_job()
  local buf
  local pcmd = { "quarto", "preview", file, "--port", "4200", "--no-browser" }
  vim.list_extend(pcmd, extra or {})
  preview_job, buf = open_term(pcmd, file,
    function() preview_job = nil end)
  local tries = 0
  local timer = vim.uv.new_timer()
  timer:start(500, 500, vim.schedule_wrap(function()
    tries = tries + 1
    local alive = vim.api.nvim_buf_is_valid(buf)
    local text = alive and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or ""
    local url = text:match("Browse at (https?://[^%s]+)")
    if url then
      A.notify("quarto preview: " .. url)
    elseif text:match("Quitting from") then
      A.notify("render 失敗 → \\qe でエラー箇所へ", vim.log.levels.ERROR)
    elseif alive and tries < 600 then
      return
    end
    timer:stop()
    timer:close()
  end))
end

-- pptx の後処理(章ラベル・表キャプションを上へ): templates/pptx_post.py(プロジェクト優先)を実行
function M.pptx_post(file, since, out)
  out = out or vim.fn.fnamemodify(file, ":r") .. ".pptx"
  local st = vim.uv.fs_stat(out)
  if not st or st.mtime.sec < (since or 0) - 1 then return end
  local script
  for dir in vim.fs.parents(file) do
    for _, c in ipairs({ dir .. "/templates/pptx_post.py", dir .. "/analysis/templates/pptx_post.py" }) do
      if vim.uv.fs_stat(c) then script = c break end
    end
    if script or vim.uv.fs_stat(dir .. "/_quarto.yml") or vim.uv.fs_stat(dir .. "/.git") then break end
  end
  script = script or (config_dir .. "/templates/pptx_post.py")
  if not vim.uv.fs_stat(script) then return end
  vim.system({ vim.g.python3_host_prog or "python3", script, out }, { text = true }, function(r)
    vim.schedule(function()
      if r.code == 0 then
        A.notify(vim.trim(r.stdout))
      else
        A.notify("pptx_post 失敗(python-pptx 要):\n" .. vim.trim(r.stderr or ""), vim.log.levels.WARN)
      end
    end)
  end)
end

-- quarto render(ファイル単体)。fmt=nil で YAML の全 format、"pptx" 等で指定形式のみ
-- プロジェクトに _quarto-embed.yml(render 時だけ embed-resources: true)があるか
function M.embed_profile(file)
  local root = vim.fs.find({ "_quarto.yml" }, { upward = true, path = vim.fn.fnamemodify(file, ":p:h") })[1]
  return root and vim.uv.fs_stat(vim.fn.fnamemodify(root, ":h") .. "/_quarto-embed.yml") ~= nil
end

function M.render(fmt, file, extra)
  if not file then
    file = vim.api.nvim_buf_get_name(0)
    if file == "" then return A.notify("ファイルを保存してから", vim.log.levels.WARN) end
    vim.cmd("silent! write")
  end
  local cmd = { "quarto", "render", file }
  if fmt then vim.list_extend(cmd, { "--to", fmt }) end
  -- html の配布用 render は 1ファイル化(_quarto-embed.yml の embed-resources: true)。preview は埋め込まず速く
  if (fmt == nil or fmt == "html") and M.embed_profile(file) then vim.list_extend(cmd, { "--profile", "embed" }) end
  vim.list_extend(cmd, extra or {})
  -- main.qmd → 出力名を親フォルダ名に(analysis/記述統計/main.qmd → 記述統計.pptx)
  -- YAML に output-file があればそちら優先。形式指定時のみ(全形式 render は quarto に任せる)
  local out
  if fmt and vim.fn.fnamemodify(file, ":t:r") == "main" then
    local has_of = false
    for _, l in ipairs(vim.fn.readfile(file, "", 60)) do
      if l:match("^%s*output%-file:") then has_of = true break end
    end
    local ext = ({ pptx = "pptx", docx = "docx", pdf = "pdf", typst = "pdf" })[fmt] or "html"
    if not has_of then
      out = vim.fn.fnamemodify(file, ":p:h") .. "/" .. vim.fn.fnamemodify(file, ":p:h:t") .. "." .. ext
      vim.list_extend(cmd, { "--output", vim.fn.fnamemodify(out, ":t") })
    end
  end
  local started = os.time()
  open_term(cmd, file, function(_, code)
    vim.schedule(function()
      if code == 0 then
        A.notify(("quarto render %s: 完了"):format(fmt or ""))
        M.pptx_post(file, started, out and out:match("%.pptx$") and out or nil)
      else
        A.notify(("quarto render 失敗 (code %d) → \\qe でエラー箇所へ"):format(code), vim.log.levels.ERROR)
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- 3. パーツ単体 render / include を開く / エラー行ジャンプ
-- ---------------------------------------------------------------------------

-- このパーツを include している main を探す(同じフォルダ → 親フォルダ)
local function find_main(part)
  local name = vim.fn.fnamemodify(part, ":t")
  local dir = vim.fn.fnamemodify(part, ":h")
  for _, d in ipairs({ dir, vim.fn.fnamemodify(dir, ":h") }) do
    for _, f in ipairs(vim.fn.glob(d .. "/*.qmd", false, true)) do
      if f ~= part and not vim.fn.fnamemodify(f, ":t"):match("^part%-preview%-") then
        for _, l in ipairs(vim.fn.readfile(f)) do
          local inc = include_of(l)
          if inc and vim.fn.fnamemodify(d .. "/" .. inc, ":p") == vim.fn.fnamemodify(part, ":p") then
            return f
          end
        end
      end
    end
  end
end

-- all=false: main の冒頭(YAML+セットアップ)+このパーツだけ
-- all=true : main の冒頭+先頭からこのパーツまでの include(前のパーツの変数を使う場合)
function M.part(all)
  local file = vim.api.nvim_buf_get_name(0)
  local line = vim.api.nvim_get_current_line()
  local inc = include_of(line)
  if inc then -- include 行の上なら、そのファイルを開く
    return vim.cmd.edit(vim.fn.fnameescape(vim.fn.fnamemodify(file, ":h") .. "/" .. inc))
  end
  vim.cmd("silent! write")
  local main = find_main(file)
  if not main then return A.notify("このファイルを include している main.qmd が見つからない", vim.log.levels.WARN) end
  local main_dir = vim.fn.fnamemodify(main, ":h")
  local target = vim.fn.fnamemodify(file, ":p")
  -- main の最初の include より前(YAML・セットアップ)+ include 行(単体: このパーツだけ / all: 先頭からこのパーツまで)
  local out, includes, in_header = {}, {}, true
  for _, l in ipairs(vim.fn.readfile(main)) do
    local i = include_of(l)
    if i then
      in_header = false
      local is_target = vim.fn.fnamemodify(main_dir .. "/" .. i, ":p") == target
      if all or is_target then includes[#includes + 1] = l end
      if is_target then break end
    elseif in_header then
      out[#out + 1] = l
    end
  end
  vim.list_extend(out, includes)
  -- 先頭 _ のファイルは quarto がプロジェクト外扱い(execute-dir が効かず出力も出ない)ので普通の名前で作り、停止時に消す
  local tmp = main_dir .. "/part-preview-" .. vim.fn.fnamemodify(file, ":t:r") .. ".qmd"
  M.stop()
  vim.fn.writefile(out, tmp)
  M.temp_files[#M.temp_files + 1] = tmp
  A.notify(("パーツ単体 preview: %s(%s)"):format(vim.fn.fnamemodify(tmp, ":t"), all and "先頭から" or "単体"))
  M.preview(tmp)
end

-- カーソル位置の ## / ### セクションだけ preview
--   level = nil: カーソル直上の見出し(## でも ### でも)/ 2: 直上の ## まで遡る
--   それより前のコードチャンクは「#| include: false」で実行だけする(読込・前処理を引き継ぐ)
function M.section(level)
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then return A.notify("ファイルを保存してから", vim.log.levels.WARN) end
  vim.cmd("silent! write")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  -- YAML ヘッダ
  local yaml_end = 0
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" then yaml_end = i break end
    end
  end
  -- 見出し行(コードチャンクの中の # コメントは除く)
  local heads, in_code = {}, false
  for i = yaml_end + 1, #lines do
    local l = lines[i]
    if l:match("^%s*```") then
      in_code = not in_code
    elseif not in_code then
      local hashes = l:match("^(#+)%s")
      if hashes then heads[#heads + 1] = { line = i, level = #hashes } end
    end
  end
  local start
  for k = #heads, 1, -1 do
    local h = heads[k]
    if h.line <= cur and h.level >= 2 and (level == nil or h.level == level) then start = h break end
  end
  if not start then
    return A.notify(level and ("カーソルより上に %s 見出しが無い"):format(("#"):rep(level)) or "カーソルより上に ## / ### 見出しが無い",
      vim.log.levels.WARN)
  end
  local stop = #lines
  for _, h in ipairs(heads) do
    if h.line > start.line and h.level <= start.level then stop = h.line - 1 break end
  end
  local out = {}
  for i = 1, yaml_end do out[#out + 1] = lines[i] end
  -- 前のチャンク: 実行だけ(表示しない)
  local i = yaml_end + 1
  while i < start.line do
    local l = lines[i]
    if l:match("^%s*```+%s*{") then
      out[#out + 1] = ""
      out[#out + 1] = l
      out[#out + 1] = "#| include: false"
      i = i + 1
      while i < start.line and not lines[i]:match("^%s*```+%s*$") do
        out[#out + 1] = lines[i]
        i = i + 1
      end
      out[#out + 1] = lines[i] or "```"
    end
    i = i + 1
  end
  out[#out + 1] = ""
  for j = start.line, stop do out[#out + 1] = lines[j] end
  local dir = vim.fn.fnamemodify(file, ":h")
  local tmp = dir .. "/section-preview-" .. vim.fn.fnamemodify(file, ":t:r") .. ".qmd"
  M.stop()
  vim.fn.writefile(out, tmp)
  M.temp_files[#M.temp_files + 1] = tmp
  A.notify(("セクション preview: %s(%d〜%d 行)"):format(vim.trim(lines[start.line]), start.line, stop))
  M.preview(tmp)
end

-- include を展開したときの行 → {元ファイル, 行}
local function expand(file, acc, depth)
  acc = acc or {}
  depth = depth or 0
  if depth > 10 or vim.fn.filereadable(file) == 0 then return acc end
  local dir = vim.fn.fnamemodify(file, ":h")
  for lnum, l in ipairs(vim.fn.readfile(file)) do
    local inc = include_of(l)
    if inc then
      expand(dir .. "/" .. inc, acc, depth + 1)
      -- quarto は include の中身の後ろに改行を1つ足す(knitr の行番号がその分ずれる)
      acc[#acc + 1] = { file = file, lnum = lnum }
    else
      acc[#acc + 1] = { file = file, lnum = lnum }
    end
  end
  return acc
end
M.expand = expand

-- 直近の render の「Quitting from main.qmd:1026-1028」から元のパーツの行へ
function M.jump_error(lnum_arg)
  local text = ""
  if M.last_term and vim.api.nvim_buf_is_valid(M.last_term) then
    text = table.concat(vim.api.nvim_buf_get_lines(M.last_term, 0, -1, false), "\n")
  end
  local fname, l1 = text:match("Quitting from ([^:%s]+):(%d+)")
  local base = M.last_file and vim.fn.fnamemodify(M.last_file, ":h") or vim.fn.expand("%:p:h")
  local file = fname and (base .. "/" .. fname) or vim.api.nvim_buf_get_name(0)
  local lnum = tonumber(lnum_arg) or tonumber(l1)
  if not lnum then
    vim.ui.input({ prompt = "エラーの行番号(Quitting from xxx.qmd:行): " }, function(input)
      if input and tonumber(input) then M.jump_error(input) end
    end)
    return
  end
  local map = expand(file)
  local hit = map[lnum]
  if not hit then return A.notify(("行 %d が範囲外(展開後 %d 行)"):format(lnum, #map), vim.log.levels.WARN) end
  -- preview/render のターミナルではなく元のウィンドウで開く
  if vim.bo.buftype == "terminal" then vim.cmd("wincmd p") end
  vim.cmd.edit(vim.fn.fnameescape(hit.file))
  vim.api.nvim_win_set_cursor(0, { hit.lnum, 0 })
  vim.cmd("normal! zz")
  A.notify(("%s:%d → %s:%d"):format(vim.fn.fnamemodify(file, ":t"), lnum, vim.fn.fnamemodify(hit.file, ":t"), hit.lnum))
end

-- ---------------------------------------------------------------------------
-- 11'. パーツ新規作成: :QNew 04_回帰 → 04_回帰.qmd を作り main.qmd に include 追記
-- ---------------------------------------------------------------------------
function M.new_part(name)
  if not name or name == "" then
    return vim.ui.input({ prompt = "新しいパーツ名(例 04_回帰): " }, function(n) if n and n ~= "" then M.new_part(n) end end)
  end
  name = name:gsub("%.qmd$", "")
  local cur = vim.api.nvim_buf_get_name(0)
  local dir = cur ~= "" and vim.fn.fnamemodify(cur, ":h") or vim.fn.getcwd()
  local main = dir .. "/main.qmd"
  if vim.fn.filereadable(main) == 0 then
    main = cur ~= "" and find_main(cur) or nil
    if main then dir = vim.fn.fnamemodify(main, ":h") end
  end
  local path = dir .. "/" .. name .. ".qmd"
  if vim.fn.filereadable(path) == 1 then return A.notify(name .. ".qmd は既にある", vim.log.levels.WARN) end
  local lang = "r"
  if main and vim.fn.filereadable(main) == 1 and table.concat(vim.fn.readfile(main), "\n"):match("\njupyter:") then lang = "python" end
  local title = name:gsub("^%d+_", "")
  local label = name:gsub("[^%w]", ""):lower()
  if label == "" or label:match("^%d") then label = "p" .. label end
  vim.fn.writefile({
    "<!-- YAMLは書かない(main.qmd の title を上書きするため)。チャンクラベル・変数名は他パーツと被らないように -->",
    "",
    "# " .. title,
    "",
    "```{" .. lang .. "}",
    "#| label: " .. label .. "-1",
    "",
    "```",
  }, path)
  if main and vim.fn.filereadable(main) == 1 then
    local lines = vim.fn.readfile(main)
    lines[#lines + 1] = "{{< include " .. name .. ".qmd >}}"
    vim.fn.writefile(lines, main)
    A.notify(("%s.qmd 作成+ %s に include 追記"):format(name, vim.fn.fnamemodify(main, ":t")))
  else
    A.notify(name .. ".qmd 作成(main.qmd が無いので include は手動で)")
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

-- ---------------------------------------------------------------------------
-- テンプレート(スライド/HTML 用 scss・section-label.html)をプロジェクトの templates/ へ
-- ---------------------------------------------------------------------------
local function project_root()
  local cur = vim.api.nvim_buf_get_name(0)
  local start = cur ~= "" and vim.fn.fnamemodify(cur, ":h") or vim.fn.getcwd()
  local found = vim.fs.find({ "_quarto.yml", ".git" }, { upward = true, path = start })[1]
  return found and vim.fn.fnamemodify(found, ":h") or vim.fn.getcwd()
end
M.project_root = project_root

-- scss・section-label.html を <root>/analysis/templates/ へ(既存は上書きしない)
function M.copy_templates(quiet)
  local root = project_root()
  local dst = root .. "/analysis/templates"
  vim.fn.mkdir(dst, "p")
  local done, skipped = {}, {}
  for _, src in ipairs(vim.fn.glob(config_dir .. "/templates/*", false, true)) do
    local name = vim.fn.fnamemodify(src, ":t")
    if vim.fn.isdirectory(src) == 0 and name ~= "_targets.R" then
      local target = dst .. "/" .. name
      if vim.fn.filereadable(target) == 1 then
        skipped[#skipped + 1] = name
      else
        vim.uv.fs_copyfile(src, target)
        done[#done + 1] = name
      end
    end
  end
  if not quiet or #done > 0 then
    A.notify(("analysis/templates/ にコピー: %s%s"):format(#done > 0 and table.concat(done, ", ") or "なし",
      #skipped > 0 and ("\n既存のため skip: " .. table.concat(skipped, ", ")) or ""))
  end
end

local function write_template(src, dst, vars)
  if vim.fn.filereadable(dst) == 1 then return false end
  local lines = vim.fn.readfile(config_dir .. "/templates/" .. src)
  for i, l in ipairs(lines) do
    for k, v in pairs(vars or {}) do
      l = l:gsub("{{" .. k .. "}}", function() return v end)
    end
    lines[i] = l
  end
  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
  vim.fn.writefile(lines, dst)
  return true
end

-- :QStudy 名前   → analysis/名前/ に _metadata.yml(title)+main.qmd(R, knitr キャッシュ)+01_記述統計.qmd
-- :QStudy! 名前  → main.qmd を Python(jupyter-cache)版で
function M.new_study(name, python)
  if not name or name == "" then
    return vim.ui.input({ prompt = "テーマ(フォルダ)名: " }, function(n) if n and n ~= "" then M.new_study(n, python) end end)
  end
  local root = project_root()
  local made = {}
  -- プロジェクト設定(無いときだけ)
  local quarto_yml = root .. "/_quarto.yml"
  if vim.fn.filereadable(quarto_yml) == 0 then
    vim.fn.writefile({
      "project:",
      "  execute-dir: project   # コードのパスはプロジェクト直下基準(here::here と一致)",
      "  # プロジェクト一括 render(quarto render)で main.qmd だけ出す(パーツ単体の出力を作らない)",
      "  # render: [\"analysis/**/main.qmd\"]",
      "  # ターミナルからの render でも pptx 後処理をする(\\qx は不要・要 python-pptx)",
      "  # post-render: analysis/templates/pptx_post.py",
    }, quarto_yml)
    made[#made + 1] = "_quarto.yml"
  elseif not table.concat(vim.fn.readfile(quarto_yml), "\n"):match("execute%-dir:%s*project") then
    A.notify("_quarto.yml に `project: execute-dir: project` が無い → パスがずれるので追加推奨", vim.log.levels.WARN)
  end
  local embed_yml = root .. "/_quarto-embed.yml"
  if vim.fn.filereadable(embed_yml) == 0 then
    vim.fn.writefile({
      "# \\qr(html render)の時だけ使うプロファイル: 画像・CSS を1つの html に埋め込む(配布用)",
      "# preview(\\qp)はこれを使わない → 埋め込みしないぶん速い",
      "# _quarto.yml / _metadata.yml / qmd に embed-resources(self-contained)を書くとそちらが優先されて preview も遅くなる",
      "format:",
      "  html:",
      "    embed-resources: true",
    }, embed_yml)
    made[#made + 1] = "_quarto-embed.yml"
  end
  if write_template("analysis/_metadata.yml", root .. "/analysis/_metadata.yml") then made[#made + 1] = "analysis/_metadata.yml" end
  M.copy_templates(true)
  local dir = root .. "/analysis/" .. name
  local part = "記述統計"
  local vars = { TITLE = name, PART = part, LANG = python and "python" or "r", LABEL = "desc" }
  if write_template("study/_metadata.yml", dir .. "/_metadata.yml", vars) then made[#made + 1] = name .. "/_metadata.yml" end
  if write_template(python and "study/main_py.qmd" or "study/main_r.qmd", dir .. "/main.qmd", vars) then made[#made + 1] = name .. "/main.qmd" end
  if write_template("study/01_part.qmd", dir .. "/01_" .. part .. ".qmd", vars) then made[#made + 1] = name .. "/01_" .. part .. ".qmd" end
  A.notify(#made > 0 and ("作成: " .. table.concat(made, ", ") .. "\nパーツ追加は :QNew 02_xxx") or "全部既にある")
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/main.qmd"))
end

-- ---------------------------------------------------------------------------
-- 5. targets
-- ---------------------------------------------------------------------------
function M.targets_init()
  local root = project_root()
  local dst = root .. "/_targets.R"
  if vim.fn.filereadable(dst) == 1 then
    return vim.cmd.edit(vim.fn.fnameescape(dst))
  end
  vim.fn.writefile(vim.fn.readfile(config_dir .. "/templates/_targets.R"), dst)
  A.notify("_targets.R を作成: " .. dst .. "\n.gitignore に _targets/ を追加推奨")
  vim.cmd.edit(vim.fn.fnameescape(dst))
end

function M.targets(what)
  local root = project_root()
  if what == "load" then
    local name = A.word()
    if name == "" then return A.notify("カーソルをターゲット名の上に", vim.log.levels.WARN) end
    return A.query("r", function(path)
      return ("targets::tar_load(%s, store = %s); .nv$out(list(text = %s), %s)"):format(
        name, A.q(root .. "/_targets"), A.q(name .. " を読み込み"), path)
    end, function(res) A.notify(res.text) end)
  end
  if what == "make" then A.notify("tar_make 実行中…") end
  A.query("r", function(path)
    return (".nv$tar(%s, %s, %s)"):format(A.q(what), A.q(root), path)
  end, function(res) A.float(res.text, "targets " .. what) end, { timeout = 3600 * 1000 })
end

-- ---------------------------------------------------------------------------
-- 8. スニペットピッカー(snippets/*.json を一覧+プレビュー → 選んで展開)
-- ---------------------------------------------------------------------------
-- JSON の任意キー: "category" = タブ、"key" = <localleader>s<key> で直接挿入
--   category が無ければファイルごとの既定(下の表)→ "その他"
local SNIP_FILE_CAT = { ["r-analysis.json"] = "R", ["python-analysis.json"] = "Python" }
local SNIP_ORDER = { "レイアウト", "図表", "callout", "文中", "スライド", "チャンク", "文書" }
-- 解析コードは \aw(分析レシピ)で入れるので、一覧には出さない(補完の prefix では使える)
local SNIP_HIDDEN = { R = true, Python = true }

local function load_snippets(ft)
  local dir = config_dir .. "/snippets"
  local ok, pkg = pcall(vim.json.decode, table.concat(vim.fn.readfile(dir .. "/package.json"), "\n"))
  if not ok then return {} end
  local out = {}
  for _, s in ipairs(pkg.contributes.snippets or {}) do
    local langs = type(s.language) == "table" and s.language or { s.language }
    if vim.tbl_contains(langs, ft) then
      local file = s.path:gsub("^%./", "")
      local okf, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(dir .. "/" .. file), "\n"))
      if okf then
        for name, sn in pairs(data) do
          local body = type(sn.body) == "table" and table.concat(sn.body, "\n") or sn.body
          local cat = sn.category or SNIP_FILE_CAT[file] or "その他"
          if not SNIP_HIDDEN[cat] then
            out[#out + 1] = {
              name = name, prefix = sn.prefix, body = body, desc = sn.description,
              cat = cat, key = sn.key,
            }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- ビジュアル選択の範囲と中身(選択を抜けてから呼ぶ)
local function visual_selection()
  local mode = vim.fn.visualmode()
  local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
  local sr, sc, er, ec = s[2] - 1, s[3] - 1, e[2] - 1, e[3]
  if mode == "V" then
    return { linewise = true, sr = sr, er = er, text = table.concat(vim.api.nvim_buf_get_lines(0, sr, er + 1, false), "\n") }
  end
  local last = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1] or ""
  ec = math.min(ec, #last)
  -- マルチバイト文字の途中で切れないよう、終端を文字の終わりまで伸ばす
  if ec > 0 and ec < #last then
    ec = ec + #vim.fn.strcharpart(last:sub(ec), 0, 1) - 1
  end
  return { sr = sr, sc = sc, er = er, ec = ec, text = table.concat(vim.api.nvim_buf_get_text(0, sr, sc, er, ec, {}), "\n") }
end

local function snippet_escape(text)
  return (text:gsub("[\\$}]", "\\%0"))
end

-- スニペットを展開。sel があれば選択範囲を消して、最初の $0 の位置に選択の中身を入れる
local function expand(body, where, sel)
  vim.api.nvim_set_current_win(where.win)
  local target -- 展開位置 { row(1始まり), col(バイト) }
  if sel then
    local pos = body:find("$0", 1, true)
    if pos then
      body = body:sub(1, pos - 1) .. snippet_escape(sel.text) .. body:sub(pos)
    end
    if sel.linewise then
      vim.api.nvim_buf_set_lines(where.buf, sel.sr, sel.er + 1, false, { "" })
      target = { sel.sr + 1, 0 }
    else
      vim.api.nvim_buf_set_text(where.buf, sel.sr, sel.sc, sel.er, sel.ec, { "" })
      target = { sel.sr + 1, sel.sc }
    end
  else
    local row = where.pos[1]
    local line = vim.api.nvim_buf_get_lines(where.buf, row - 1, row, false)[1] or ""
    if where.insert then
      target = where.pos
    elseif line:match("^%s*$") then
      target = { row, 0 }
    elseif body:find("\n") then
      -- 複数行のスニペットは下の行に
      vim.api.nvim_buf_set_lines(where.buf, row, row, false, { "" })
      target = { row + 1, 0 }
    else
      -- 1行のもの(脚注・色など)はカーソル文字の後ろに
      target = { row, where.pos[2] + #vim.fn.strcharpart(line:sub(where.pos[2] + 1), 0, 1) }
    end
  end
  -- インサートモードに入ったのを確かめてから(InsertEnter)カーソルを置いて展開する
  --   行末にも置けるのはインサート中だけなので、タイミング任せにしない
  local function go()
    pcall(vim.api.nvim_win_set_cursor, where.win, target)
    vim.snippet.expand(body)
  end
  if vim.fn.mode() == "i" then
    return vim.schedule(go)
  end
  vim.api.nvim_create_autocmd("InsertEnter", {
    once = true,
    callback = function()
      vim.schedule(go)
    end,
  })
  local tline = vim.api.nvim_buf_get_lines(where.buf, target[1] - 1, target[1], false)[1] or ""
  vim.cmd(target[2] >= #tline and "startinsert!" or "startinsert")
end

-- opts.visual = true: ビジュアル選択を包む(キーマップの x モードから)
function M.snippets(opts)
  opts = opts or {}
  local sel
  if opts.visual then
    vim.cmd("normal! \27")
    sel = visual_selection()
  end
  local where = A.capture_pos()
  local ft = vim.bo.filetype
  local list = load_snippets(ft)
  if #list == 0 then return A.notify("スニペットなし(" .. ft .. ")", vim.log.levels.WARN) end
  local items = {}
  for _, s in ipairs(list) do
    local prefix = type(s.prefix) == "table" and table.concat(s.prefix, ",") or (s.prefix or "")
    -- 見やすさのためプレビューではプレースホルダを中身だけに
    local shown = s.body:gsub("%${%d+|([^,|}]*)[^}]*|}", "%1"):gsub("%${%d+:([^}]*)}", "%1"):gsub("%${%d+}", ""):gsub("%$%d+", "")
    shown = shown:gsub("\\%$", "$")
    items[#items + 1] = {
      text = s.cat .. " " .. s.name .. " " .. prefix,
      label = s.name,
      detail = prefix .. (s.key and ("  \\s" .. s.key) or ""),
      cat = s.cat,
      body = s.body,
      preview = { text = shown, ft = ft == "quarto" and "markdown" or ft },
    }
  end
  A.tab_picker({
    name = "スニペット(" .. ft .. ")" .. (sel and " 選択を包む" or ""),
    items = items,
    order = SNIP_ORDER,
    on_pick = function(picked)
      expand(picked[1].body, where, sel)
    end,
  })
end

-- "key" を持つスニペットを <localleader>s<key> に割り当てる(バッファローカル)
--   ノーマル/インサート位置に挿入、ビジュアルなら選択を包む
function M.snippet_keys(buf)
  local ft = vim.bo[buf].filetype
  for _, s in ipairs(load_snippets(ft)) do
    if s.key then
      local lhs = "<localleader>s" .. s.key
      vim.keymap.set("n", lhs, function()
        expand(s.body, A.capture_pos())
      end, { buffer = buf, desc = s.name })
      vim.keymap.set("x", lhs, function()
        vim.cmd("normal! \27")
        local sel = visual_selection()
        expand(s.body, A.capture_pos(), sel)
      end, { buffer = buf, desc = s.name .. "(選択を包む)" })
    end
  end
  vim.keymap.set("n", "<localleader>ss", M.snippets, { buffer = buf, desc = "スニペット一覧(タブ)" })
  vim.keymap.set("x", "<localleader>ss", function()
    M.snippets({ visual = true })
  end, { buffer = buf, desc = "スニペット一覧 → 選択を包む" })
end

-- コードチャンクの範囲 { {s, e}, ... }(s = ```{ の行, e = 閉じ ``` の行)
local function chunk_ranges()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local res, open = {}, nil
  for i, l in ipairs(lines) do
    if not open and l:match("^%s*```+%s*{") then
      open = i
    elseif open and l:match("^%s*```+%s*$") then
      res[#res + 1] = { open, i }
      open = nil
    end
  end
  return res
end

-- dir = 1: 次のチャンク / -1: 前のチャンク。本文の先頭行へ移動
function M.goto_chunk(dir)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local ranges = chunk_ranges()
  local target
  if dir > 0 then
    for _, r in ipairs(ranges) do
      if r[1] > cur then target = r; break end
    end
  else
    for i = #ranges, 1, -1 do
      local r = ranges[i]
      if r[2] < cur then target = r; break end   -- 今いるチャンクは飛ばす
    end
  end
  if not target then return false end
  local row = math.min(target[1] + 1, target[2])
  -- #| オプション行は飛ばす
  while row < target[2] and (vim.fn.getline(row):match("^%s*#|")) do row = row + 1 end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  return true
end

-- 今のチャンクを実行して次のチャンクへ(最後のチャンクならその場)
function M.run_next()
  require("quarto.runner").run_cell()
  if vim.fn.mode():match("^i") then vim.cmd("stopinsert") end
  M.goto_chunk(1)
end

return M
