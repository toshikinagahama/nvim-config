return {
  "stevearc/oil.nvim",
  lazy = false,
  opts = {
    view_options = {
      show_hidden = true,
      is_always_hidden = function(name)
        return name:match("%.otter%.") ~= nil
      end,
    },
    delete_to_trash = true,
  },
  keys = { { "-", "<cmd>Oil<cr>", desc = "親フォルダを開く(oil)" } },
}
