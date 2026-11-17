-- CSV / TSV を列そろえで表示(ファイルの中身は変えない)
--   .csv / .tsv を開くと自動でオン。<localleader>cv で切り替え
return {
  {
    "hat0uma/csvview.nvim",
    ft = { "csv", "tsv" },
    cmd = { "CsvViewEnable", "CsvViewDisable", "CsvViewToggle" },
    opts = {
      parser = { comments = { "#", "//" } },
      view = {
        display_mode = "border",
        -- 見出し行は自動で判定して上に固定(既定)。横スクロールしても 1 列目(ID など)は残す
        sticky_columns = { enabled = true, count = 1 },
      },
      keymaps = {
        -- 列のテキストオブジェクト(dif / vaf など)と、Tab / S-Tab でセル移動
        textobject_field_inner = { "if", mode = { "o", "x" } },
        textobject_field_outer = { "af", mode = { "o", "x" } },
        jump_next_field_end = { "<Tab>", mode = { "n", "v" } },
        jump_prev_field_end = { "<S-Tab>", mode = { "n", "v" } },
        jump_next_row = { "<Enter>", mode = { "n", "v" } },
        jump_prev_row = { "<S-Enter>", mode = { "n", "v" } },
      },
    },
    config = function(_, opts)
      require("csvview").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("csvview_auto", { clear = true }),
        pattern = { "csv", "tsv" },
        callback = function(ev)
          require("csvview").enable(ev.buf)
        end,
      })
      -- 最初の csv を開いたときは FileType が先に済んでいるので、ここで有効にする
      local ft = vim.bo.filetype
      if ft == "csv" or ft == "tsv" then
        require("csvview").enable(0)
      end
    end,
    keys = {
      { "<localleader>cv", "<cmd>CsvViewToggle<cr>", ft = { "csv", "tsv" }, desc = "CSV 列そろえ表示 切替" },
    },
  },
}
