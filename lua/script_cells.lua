-- .py / .R の "# %%" セルを Jupyter 風に実行する(molten)。after/ftplugin から setup(kernel) で有効化
local M = {}

local MARK = [[^\s*# %%]]

local function cell_bounds()
  local last = vim.fn.line("$")
  local prev = vim.fn.search(MARK, "bcnW")
  local next = vim.fn.search(MARK, "nW")
  local first = prev == 0 and 1 or prev + 1
  local stop = next == 0 and last or next - 1
  return first, stop, next
end

function M.setup(kernel)
  local function ensure_kernel()
    local ok, running = pcall(vim.fn.MoltenRunningKernels, true)
    if not ok or not vim.tbl_contains(running, kernel) then
      vim.cmd("MoltenInit " .. kernel)
    end
  end

  local function run(first, stop)
    if first > stop then
      return
    end
    -- 未起動なら起動し Ready 後に実行(起動直後に送ると最初のセルが On Hold で固まる)
    require("molten_ready").run(kernel, function()
      vim.fn.MoltenEvaluateRange(kernel, first, stop)
    end)
  end

  local function run_cell(move)
    local first, stop, next = cell_bounds()
    run(first, stop)
    if move and next > 0 then
      vim.api.nvim_win_set_cursor(0, { math.min(next + 1, vim.fn.line("$")), 0 })
    end
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = true, desc = desc })
  end

  map("<localleader>r", function() run_cell(false) end, "Run cell")
  map("<localleader>x", function() run_cell(true) end, "Run cell and go to next")
  map("<S-CR>", function() run_cell(true) end, "Run cell and go to next")
  map("<localleader>ra", function()
    local _, stop = cell_bounds()
    run(1, stop)
  end, "Run cell and above")
  map("<localleader>rA", function() run(1, vim.fn.line("$")) end, "Run all")
  map("]x", function()
    if vim.fn.search(MARK, "W") > 0 then
      vim.cmd("normal! j")
    end
  end, "Next cell")
  map("[x", function()
    local first = cell_bounds()
    vim.api.nvim_win_set_cursor(0, { first, 0 })
    if vim.fn.search(MARK, "bW") == 0 then
      return
    end
    local prev = vim.fn.search(MARK, "bW")
    vim.api.nvim_win_set_cursor(0, { prev == 0 and 1 or prev + 1, 0 })
  end, "Previous cell")
  map("<localleader>c", function()
    vim.api.nvim_put({ "", "# %%", "" }, "l", true, true)
  end, "Insert cell below")
  vim.keymap.set("v", "<localleader>r", ":<C-u>MoltenEvaluateVisual<cr>", { buffer = true, desc = "Run selection" })
end

return M
