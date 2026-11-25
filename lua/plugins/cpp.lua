-- C / C++ support (clangd + cmake extras are enabled in lazyvim.json, plus dap.core (codelldb debugger))
-- WSL (Ubuntu) prerequisites: sudo apt install build-essential gdb cmake unzip
-- Mason has no clangd build for linux-arm64 (Raspberry Pi): use apt's clangd there
local arm = vim.uv.os_uname().machine:match("aarch64") ~= nil

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "clang-format" }) -- codelldb comes from mason-nvim-dap (dap.core)
      if arm then
        opts.ensure_installed = vim.tbl_filter(function(n)
          return n ~= "clangd"
        end, opts.ensure_installed)
      else
        table.insert(opts.ensure_installed, "clangd")
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = not arm, -- on arm64 use the system clangd (sudo apt install clangd)
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
            -- let clangd find the system headers of gcc/g++ (WSL / Linux)
            "--query-driver=/usr/bin/gcc,/usr/bin/g++,/usr/bin/cc,/usr/bin/c++,/usr/bin/clang*",
          },
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
    },
  },
}
