-- 分析補助のキー割り当て(qmd / .py / .R)。実装は lua/analysis/*.lua
--   カーネルの値を使う機能(列名・変数一覧・表表示・peek・TSV)は、先にセルを実行してカーネルを起動しておく
local ft = { "quarto", "python", "r" }
local function A()
  return require("analysis")
end
local function Q()
  return require("analysis.quarto")
end
local function X()
  return require("analysis.extra")
end

vim.api.nvim_create_user_command("QNew", function(o)
  Q().new_part(o.args)
end, { nargs = "?", desc = "パーツqmd作成+main.qmdにinclude" })
vim.api.nvim_create_user_command("QStudy", function(o)
  Q().new_study(o.args, o.bang)
end, { nargs = "?", bang = true, desc = "analysis/<名前>/ に main.qmd 等を作成(! で Python 版)" })
vim.api.nvim_create_user_command("AnalysisTemplates", function()
  Q().copy_templates()
end, { desc = "scss等を analysis/templates/ へ" })
vim.api.nvim_create_user_command("AnalysisTargetsInit", function()
  Q().targets_init()
end, { desc = "_targets.R 雛形を作成" })
vim.api.nvim_create_user_command("AnalysisReload", function()
  A().reload()
end, { desc = "カーネル側ヘルパ再読込" })
vim.api.nvim_create_user_command("AnalysisKeys", function()
  require("analysis.extra").keys()
end, { desc = "キー割り当て早見表" })
vim.api.nvim_create_user_command("AnalysisErr", function(o)
  Q().jump_error(o.args)
end, { nargs = "?", desc = "render エラー行へ" })

return {
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<localleader>d", group = "データ表示" },
        { "<localleader>p", group = "peek(カーソル下)" },
        { "<localleader>t", group = "targets" },
        { "<localleader>v", group = "変数" },
        { "<localleader>y", group = "コピー" },
        { "<localleader>a", group = "分析レシピ" },
        { "<localleader>q", group = "quarto" },
        { "<localleader>i", group = "挿入" },
      },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      opts.sections = opts.sections or {}
      opts.sections.lualine_x = opts.sections.lualine_x or {}
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return require("analysis").statusline()
        end,
        cond = function()
          return vim.tbl_contains(ft, vim.bo.filetype) and vim.fn.exists("*MoltenRunningKernels") == 1
        end,
      })
    end,
  },
  {
    "benlubas/molten-nvim",
    optional = true,
    keys = {
      -- カーネルの値を使う
      {
        "<localleader>n",
        function()
          A().columns()
        end,
        ft = ft,
        desc = "列名ピッカー(Tab複数)→挿入",
      },
      {
        "<M-c>",
        function()
          A().columns()
        end,
        mode = "i",
        ft = ft,
        desc = "列名ピッカー→挿入",
      },
      {
        "<localleader>vv",
        function()
          A().objects()
        end,
        ft = ft,
        desc = "変数一覧(Enter挿入/<C-v>表)",
      },
      {
        "<localleader>dv",
        function()
          A().view()
        end,
        mode = { "n", "v" },
        ft = ft,
        desc = "表を figviewer で見る(:8766)",
      },
      {
        "<localleader>ps",
        function()
          A().peek("summary")
        end,
        mode = { "n", "v" },
        ft = ft,
        desc = "summary",
      },
      {
        "<localleader>pt",
        function()
          A().peek("table")
        end,
        mode = { "n", "v" },
        ft = ft,
        desc = "度数表",
      },
      {
        "<localleader>ph",
        function()
          A().peek("hist")
        end,
        mode = { "n", "v" },
        ft = ft,
        desc = "ヒストグラム",
      },
      {
        "<localleader>yt",
        function()
          A().yank_table()
        end,
        mode = { "n", "v" },
        ft = ft,
        desc = "表をTSVでコピー(Excel貼付)",
      },
      {
        "<localleader>aw",
        function()
          require("analysis.recipes").pick()
        end,
        ft = ft,
        desc = "分析レシピ",
      },
      {
        "<localleader>in",
        function()
          require("analysis.recipes").run("rename")
        end,
        ft = ft,
        desc = "列名変更(rename雛形)",
      },
      -- targets(R)
      {
        "<localleader>tm",
        function()
          Q().targets("make")
        end,
        ft = ft,
        desc = "tar_make",
      },
      {
        "<localleader>to",
        function()
          Q().targets("outdated")
        end,
        ft = ft,
        desc = "tar_outdated",
      },
      {
        "<localleader>tl",
        function()
          Q().targets("load")
        end,
        ft = ft,
        desc = "tar_load(カーソル下)",
      },
      -- カーネル不要
      {
        "<localleader>o",
        function()
          A().outline()
        end,
        ft = ft,
        desc = "アウトライン(見出し/チャンク)",
      },
      {
        "<localleader>is",
        function()
          Q().snippets()
        end,
        ft = ft,
        desc = "スニペット一覧から挿入",
      },
      {
        "<C-M-s>",
        function()
          Q().snippets()
        end,
        mode = { "n", "i" },
        ft = ft,
        desc = "スニペット一覧から挿入",
      },
      {
        "<localleader>qi",
        function()
          Q().part(false)
        end,
        ft = "quarto",
        desc = "このパーツだけ preview / include行なら開く",
      },
      {
        "<localleader>qI",
        function()
          Q().part(true)
        end,
        ft = "quarto",
        desc = "先頭〜このパーツまで preview",
      },
      {
        "<localleader>qe",
        function()
          Q().jump_error()
        end,
        ft = "quarto",
        desc = "render エラー行へジャンプ",
      },
      -- 追加分(lua/analysis/extra.lua)
      {
        "<localleader>it",
        function()
          X().convert()
        end,
        ft = ft,
        desc = "型変換コードを挿入(列ピッカー)",
      },
      {
        "<localleader>yw",
        function()
          X().docx()
        end,
        ft = ft,
        desc = "カーソル下の表 → Word(docx)",
      },
      {
        "<localleader>if",
        function()
          X().read_file()
        end,
        ft = ft,
        desc = "データファイル → 読込コード",
      },
      {
        "<localleader>iv",
        function()
          X().paste_table()
        end,
        ft = ft,
        desc = "Excel の範囲を貼り付け → df",
      },
      {
        "<localleader>ix",
        function()
          X().crossref()
        end,
        ft = { "quarto", "markdown" },
        desc = "相互参照 @fig- @tbl- を挿入",
      },
      {
        "<M-r>",
        function()
          X().crossref()
        end,
        mode = "i",
        ft = { "quarto", "markdown" },
        desc = "相互参照を挿入",
      },
      {
        "<localleader>?",
        function()
          X().keys()
        end,
        ft = ft,
        desc = "キー割り当て早見表(Enterで実行)",
      },
      {
        "<localleader>/",
        function()
          X().toggle_cell_comment()
        end,
        ft = ft,
        desc = "チャンク/セルをまとめてコメント切替",
      },
      -- qmd: 実行して次のチャンクへ(.py/.R の # %% セルは script_cells.lua 側)
      {
        "<localleader>x",
        function()
          Q().run_next()
        end,
        ft = "quarto",
        desc = "Run cell and go to next",
      },
      {
        "<S-CR>",
        function()
          Q().run_next()
        end,
        ft = "quarto",
        desc = "Run cell and go to next",
      },
      {
        "]x",
        function()
          Q().goto_chunk(1)
        end,
        ft = "quarto",
        desc = "次のチャンク",
      },
      {
        "[x",
        function()
          Q().goto_chunk(-1)
        end,
        ft = "quarto",
        desc = "前のチャンク",
      },
    },
  },
}
