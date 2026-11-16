-- カーネルが Ready になってから fn を実行する(未起動なら MoltenInit)
-- 起動直後(MoltenRunningKernels には載るが未Ready)に送ると jupyter_client の wait_for_ready が
-- IOPub を捨てる → 最初のセルが On Hold のまま固まる。
-- v2: Ready を自前で記録 → \mi 直後や起動待ち中の連打も Ready まで溜めて順番通り流す。
--     起動時に読み込むこと(plugins/quarto-molten.lua 先頭で require)。Ready 通知の取り逃し防止。
local M = {}

local ready = {} -- kernel_id -> true
local pending = {} -- kernel_id -> { fn, ... }

local grp = vim.api.nvim_create_augroup("molten_ready", { clear = true })
vim.api.nvim_create_autocmd("User", {
  group = grp,
  pattern = "MoltenKernelReady",
  callback = function(ev)
    local id = ev.data and ev.data.kernel_id
    if not id then
      return
    end
    -- rplugin の通知中に Molten を呼ぶと詰まるので schedule。
    -- Ready 記録も flush と同時に(間に押された \r が先に走って順番が逆転しないように)
    vim.schedule(function()
      ready[id] = true
      local fns = pending[id] or {}
      pending[id] = nil
      for _, fn in ipairs(fns) do
        fn()
      end
    end)
  end,
})
vim.api.nvim_create_autocmd("User", {
  group = grp,
  pattern = "MoltenDeinitPost",
  callback = function()
    vim.schedule(function()
      local ok, all = pcall(vim.fn.MoltenRunningKernels, false)
      if not ok then
        return
      end
      for id in pairs(ready) do
        if not vim.tbl_contains(all, id) then
          ready[id] = nil
        end
      end
    end)
  end,
})

local function running(kernel)
  local ok, ids = pcall(vim.fn.MoltenRunningKernels, true)
  return ok and vim.tbl_contains(ids, kernel)
end

function M.run(kernel, fn)
  if running(kernel) and ready[kernel] then
    return fn()
  end
  local buf = vim.api.nvim_get_current_buf()
  local function call()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, fn)
    end
  end
  if pending[kernel] then -- 起動待ち中: 順番に溜める
    table.insert(pending[kernel], call)
    return
  end
  pending[kernel] = { call }
  if not running(kernel) then -- 起動中(\mi 直後など)なら二重起動しない
    ready[kernel] = nil
    vim.cmd("MoltenInit " .. kernel)
  end
  vim.defer_fn(function()
    local fns = pending[kernel]
    if not fns then
      return
    end
    pending[kernel] = nil
    if running(kernel) then -- Ready 通知を取り逃した等: 動いてはいるので流す
      ready[kernel] = true
      for _, f in ipairs(fns) do
        f()
      end
    else
      vim.notify(kernel .. " が120秒で起動せず → 実行取り消し。もう一度 \\r", vim.log.levels.WARN)
    end
  end, 120000)
end

return M
