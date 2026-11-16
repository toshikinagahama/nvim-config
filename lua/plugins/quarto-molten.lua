-- qmd / .py / .R / .ipynb データ分析: molten(Jupyterカーネル実行) + quarto-nvim
-- Mac / Pi / 職場サーバ 共通。図: Python=figviewer(http://localhost:8766)、R=httpgd(\hh → http://localhost:8765)
-- quarto preview は http://localhost:4200(SSH 越しはポート転送)
local config_dir = vim.fn.stdpath("config")
require("molten_ready") -- Ready 通知を起動時から監視(\r の On Hold 対策)

-- インライン画像はOFF(スクロール時の描画崩れ・クラッシュ回避)。出力はテキストのみ
vim.g.molten_image_provider = "none"
vim.g.molten_auto_open_output = false -- セルに乗るたびの出力ポップアップを止める(見る時は \mo)
vim.g.molten_virt_text_output = true
vim.g.molten_virt_lines_off_by_1 = true
vim.g.molten_virt_text_max_lines = 30
vim.g.molten_output_win_max_height = 30
vim.g.molten_wrap_output = true

-- qmdのセル言語 → カーネル名。未起動なら起動してから実行
local molten_kernels = { python = "python3", r = "ir" }

local function molten_runner(cell, ignore_cols)
  local kernel = molten_kernels[cell.lang]
  if not kernel then
    return require("quarto.runner.molten").run(cell, ignore_cols)
  end
  local r = cell.range
  -- 未起動なら起動し Ready 後に実行(起動直後に送ると最初のセルが On Hold で固まる)
  require("molten_ready").run(kernel, function()
    if ignore_cols then
      vim.fn.MoltenEvaluateRange(kernel, r.from[1] + 1, r.to[1])
    else
      vim.fn.MoltenEvaluateRange(kernel, r.from[1] + 1, r.to[1], r.from[2] + 1, r.to[2] + 1)
    end
  end)
end

-- httpgd(R図のブラウザ表示)。実体は r/httpgd.R(IRkernelのセル毎デバイスに対応済み、ポート8765固定)
local function httpgd(call)
  local kernel = vim.iter(vim.fn.MoltenRunningKernels(true)):find(function(id)
    return vim.startswith(id, "ir")
  end)
  if not kernel then
    return vim.notify("Rカーネル未起動: \\mi で ir を起動してから", vim.log.levels.WARN)
  end
  vim.cmd(('MoltenEvaluateArgument %s {source("%s/r/httpgd.R");%s}'):format(kernel, config_dir, call))
end

-- quarto preview / render の実体は lua/analysis/quarto.lua(パーツ単体 preview・エラー行ジャンプもそこ)

-- チャンク挿入: カーソルがチャンク内ならそのチャンクの後ろ、外なら現在行の下に入れて中で insert
local function insert_chunk(lang)
  return function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local inside, at = false, row
    for i = row, 1, -1 do
      if lines[i]:match("^%s*```%s*{") then inside = true; break end
      if lines[i]:match("^%s*```%s*$") and i ~= row then break end
    end
    if inside then
      for i = row + 1, #lines do
        if lines[i]:match("^%s*```%s*$") then at = i; break end
      end
    end
    vim.api.nvim_buf_set_lines(0, at, at, false, { "", "```{" .. lang .. "}", "", "```", "" })
    vim.api.nvim_win_set_cursor(0, { at + 3, 0 })
    vim.cmd("startinsert")
  end
end

return {
  {
    "jmbuhr/otter.nvim",
    -- 仮想ファイルを実際に書き出す(lintrが実ファイルを要求するため)。*.otter.* は .gitignore へ
    opts = { buffers = { write_to_disk = true } },
  },
  {
    "quarto-dev/quarto-nvim",
    ft = { "quarto" },
    dependencies = { "jmbuhr/otter.nvim", "nvim-treesitter/nvim-treesitter" },
    opts = {
      lspFeatures = {
        enabled = true,
        languages = { "r", "python", "bash", "html" },
        chunks = "all",
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        enabled = true,
        default_method = molten_runner,
      },
    },
    keys = {
      { "<localleader>r", function() require("quarto.runner").run_cell() end, ft = "quarto", desc = "Run cell" },
      { "<localleader>ra", function() require("quarto.runner").run_above() end, ft = "quarto", desc = "Run cell and above" },
      { "<localleader>rA", function() require("quarto.runner").run_all(true) end, ft = "quarto", desc = "Run all" },
      { "<localleader>r", function() require("quarto.runner").run_range() end, mode = "v", ft = "quarto", desc = "Run selection" },
      { "<localleader>qp", function() require("analysis.quarto").preview() end, ft = "quarto", desc = "Quarto preview (http://localhost:4200)" },
      { "<localleader>qq", function() require("analysis.quarto").stop() end, ft = "quarto", desc = "Quarto preview停止" },
      { "<localleader>qr", function() require("analysis.quarto").render() end, ft = "quarto", desc = "Quarto render(YAMLの全format)" },
      { "<localleader>qx", function() require("analysis.quarto").render("pptx") end, ft = "quarto", desc = "Quarto render → pptx" },
      { "<localleader>ip", insert_chunk("python"), ft = "quarto", desc = "Insert python chunk" },
      { "<localleader>ir", insert_chunk("r"), ft = "quarto", desc = "Insert r chunk" },
      { "<C-M-p>", insert_chunk("python"), mode = { "n", "i" }, ft = "quarto", desc = "Insert python chunk" },
      { "<C-M-r>", insert_chunk("r"), mode = { "n", "i" }, ft = "quarto", desc = "Insert r chunk" },
    },
  },
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    ft = { "quarto", "python", "r" },
    build = ":UpdateRemotePlugins",
    keys = {
      { "<localleader>mi", "<cmd>MoltenInit<cr>", desc = "Molten: pick kernel" },
      { "<localleader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Molten: focus output" },
      { "<localleader>md", "<cmd>MoltenDelete<cr>", desc = "Molten: delete cell" },
      { "<localleader>ml", "<cmd>MoltenEvaluateLine<cr>", desc = "Molten: run line" },
      { "<localleader>mc", "<cmd>MoltenReevaluateCell<cr>", desc = "Molten: re-run cell" },
      { "<localleader>mr", ":<C-u>MoltenEvaluateVisual<cr>", mode = "v", desc = "Molten: run selection" },
      { "<localleader>hh", function() httpgd("hgd_start()") end, desc = "httpgd: start (http://localhost:8765)" },
      { "<localleader>hu", function() httpgd("hgd_show_url()") end, desc = "httpgd: show URL" },
      { "<localleader>hc", function() httpgd("hgd_stop()") end, desc = "httpgd: stop" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "r", "python", "markdown", "markdown_inline", "yaml", "bash", "html" })
    end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "pyrefly", "ruff", "air" })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Python は Positron と同じ Pyrefly(設定はプロジェクトの pyrefly.toml)
        pyright = { enabled = false },
        basedpyright = { enabled = false },
        pyrefly = {},
        -- R は CRAN の languageserver(Mason版は使わない)。ホーム全体を走査しないよう root を明示
        r_language_server = {
          mason = false,
          root_markers = { ".lintr", "_quarto.yml", ".git" },
        },
      },
    },
  },
}
