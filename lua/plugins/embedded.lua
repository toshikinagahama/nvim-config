-- Embedded development: PlatformIO / ESP-IDF / Zephyr
-- LSP: clangd + compile_commands.json (all three generate it)
-- Build/flash/monitor: <leader>m* (auto-detects project type)

local home = vim.env.HOME
local IDF_PATH = vim.env.IDF_PATH or (home .. "/esp/esp-idf")
local ZEPHYR_WS = vim.env.ZEPHYR_WS or (home .. "/zephyrproject")

---@return "pio"|"idf"|"zephyr"|nil, string|nil
local function detect()
  local buf = vim.api.nvim_buf_get_name(0)
  local start = buf ~= "" and vim.fs.dirname(buf) or vim.uv.cwd()

  local pio = vim.fs.find("platformio.ini", { path = start, upward = true })[1]
  if pio then
    return "pio", vim.fs.dirname(pio)
  end

  -- walk every CMakeLists.txt upward; the top-level one decides
  local found
  for _, f in ipairs(vim.fs.find("CMakeLists.txt", { path = start, upward = true, limit = math.huge })) do
    local fd = io.open(f)
    if fd then
      local s = fd:read("*a")
      fd:close()
      if s:find("find_package%s*%(%s*Zephyr") then
        found = { "zephyr", vim.fs.dirname(f) }
      elseif s:find("IDF_PATH") and s:find("project%.cmake") then
        found = { "idf", vim.fs.dirname(f) }
      end
    end
  end
  if found then
    return found[1], found[2]
  end
end

-- ESP-IDF python envs are built with Python 3.13 (system python3 is 3.14 = unsupported)
local IDF_PY = home .. "/.local/share/uv/python/cpython-3.13-macos-aarch64-none/bin"

-- per project: vim.g.idf_path = "~/esp/esp-idf-v6.1" (default: $IDF_PATH or ~/esp/esp-idf = v5.2.1)
local function idf(args)
  -- activated env (:IdfEnv, or nvim started after `get_idf`). EIM's idf.py is a fish function, not on PATH
  local penv = vim.env.IDF_PYTHON_ENV_PATH
  if vim.env.IDF_PATH and penv and not vim.g.idf_path then
    return string.format(
      "%s %s %s",
      vim.fn.shellescape(penv .. "/bin/python"),
      vim.fn.shellescape(vim.env.IDF_PATH .. "/tools/idf.py"),
      args
    )
  end
  if vim.fn.executable("idf.py") == 1 and vim.env.IDF_PATH and not vim.g.idf_path then
    return "idf.py " .. args
  end
  local path = vim.fn.expand(vim.g.idf_path or IDF_PATH)
  return string.format(
    "fish -c 'set -gx PATH %s $PATH; source %s/export.fish >/dev/null 2>&1; idf.py %s'",
    IDF_PY,
    path,
    args
  )
end

-- :IdfEnv [version] = `get_idf` inside nvim. Loads ~/.espressif/tools/activate_idf_v<version>.fish
-- (EIM) into this nvim's environment, so <leader>m* runs idf.py with that IDF + venv.
local EIM_TOOLS = home .. "/.espressif/tools"

local function idf_versions()
  local vers = {}
  for _, f in ipairs(vim.fn.glob(EIM_TOOLS .. "/activate_idf_v*.fish", false, true)) do
    vers[#vers + 1] = f:match("activate_idf_v(.+)%.fish$")
  end
  table.sort(vers, function(a, b) return vim.version.lt(a, b) end)
  return vers
end

local function idf_env(ver)
  if not ver or ver == "" then
    local vers = idf_versions()
    ver = vers[#vers]
    if not ver then
      vim.notify("IdfEnv: no " .. EIM_TOOLS .. "/activate_idf_v*.fish", vim.log.levels.ERROR)
      return
    end
  end
  local script = string.format("%s/activate_idf_v%s.fish", EIM_TOOLS, ver)
  if not vim.uv.fs_stat(script) then
    vim.notify("IdfEnv: not found: " .. script, vim.log.levels.ERROR)
    return
  end
  -- the script refuses to run unless fish is interactive
  local r = vim.system({ "fish", "--no-config", "-i", "-c", "source " .. vim.fn.shellescape(script) .. " >/dev/null 2>&1; and env -0" }, { text = true }):wait()
  if r.code ~= 0 then
    vim.notify("IdfEnv: failed to source " .. script, vim.log.levels.ERROR)
    return
  end
  for entry in r.stdout:gmatch("([^%z]+)") do
    local k, v = entry:match("^([%w_]+)=(.*)$")
    if k and not k:match("^fish_") and k ~= "SHLVL" and k ~= "PWD" and k ~= "_" then
      vim.env[k] = v
    end
  end
  vim.g.idf_path = nil -- use the activated idf.py, not the export.fish fallback
  vim.notify(string.format("IdfEnv: ESP-IDF v%s (%s)", ver, vim.env.IDF_PATH))
end

local function west(args)
  local bin = vim.fn.executable("west") == 1 and "west" or (ZEPHYR_WS .. "/.venv/bin/west")
  return bin .. " " .. args
end

local pio = vim.fn.executable("pio") == 1 and "pio" or (home .. "/.platformio/penv/bin/pio")

-- vim.g.zephyr_board = "nrf52840dk/nrf52840" etc. (set per project via .nvim.lua / exrc)
local function zboard()
  return vim.g.zephyr_board and (" -b " .. vim.g.zephyr_board) or ""
end

local cmds = {
  pio = {
    build = pio .. " run",
    flash = pio .. " run -t upload",
    monitor = pio .. " device monitor",
    flash_monitor = pio .. " run -t upload -t monitor",
    clean = pio .. " run -t clean",
    compiledb = pio .. " run -t compiledb",
    menuconfig = pio .. " run -t menuconfig",
  },
  idf = {
    build = function() return idf("build") end,
    flash = function() return idf("flash") end,
    monitor = function() return idf("monitor") end,
    flash_monitor = function() return idf("flash monitor") end,
    clean = function() return idf("fullclean") end,
    compiledb = function() return idf("reconfigure") end,
    menuconfig = function() return idf("menuconfig") end,
  },
  zephyr = {
    build = function() return west("build" .. zboard()) end,
    flash = west("flash"),
    monitor = vim.g.zephyr_monitor or (pio .. " device monitor"),
    flash_monitor = function() return west("flash") .. " && " .. (vim.g.zephyr_monitor or (pio .. " device monitor")) end,
    clean = function() return west("build -p always" .. zboard()) end,
    compiledb = function() return west("build -p always" .. zboard()) end,
    menuconfig = west("build -t menuconfig"),
  },
}

local function run(action)
  return function()
    local kind, root = detect()
    if not kind then
      vim.notify("No PlatformIO / ESP-IDF / Zephyr project found", vim.log.levels.WARN)
      return
    end
    local cmd = cmds[kind][action]
    if type(cmd) == "function" then
      cmd = cmd()
    end
    vim.cmd("silent! wall")
    Snacks.terminal(cmd, {
      cwd = root,
      auto_close = false,
      win = { position = "bottom", height = 0.35 },
    })
    if action == "compiledb" or action == "build" then
      -- let clangd pick up the new compile_commands.json
      vim.defer_fn(function() pcall(vim.cmd, "LspRestart clangd") end, 500)
    end
  end
end

local query_driver = table.concat({
  home .. "/.platformio/packages/toolchain-*/bin/*",
  home .. "/.espressif/tools/*/*/*/bin/*",
  home .. "/zephyr-sdk-*/gnu/*/bin/*",
  "/opt/homebrew/bin/arm-none-eabi-*",
  -- system compilers (WSL / Linux desktop C/C++): lets clangd find gcc/g++ standard headers
  "/usr/bin/gcc*",
  "/usr/bin/g++*",
  "/usr/bin/cc",
  "/usr/bin/c++",
  "/usr/bin/clang*",
}, ",")

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=never",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--fallback-style=llvm",
            "--query-driver=" .. query_driver,
          },
        },
      },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "c", "cpp", "cmake", "devicetree", "kconfig", "ini" } },
  },

  {
    "folke/which-key.nvim",
    opts = { spec = { { "<leader>m", group = "mcu (pio/idf/zephyr)", icon = "󰻠" } } },
  },

  {
    "LazyVim/LazyVim",
    keys = {
      { "<leader>mb", run("build"), desc = "Build" },
      { "<leader>mf", run("flash"), desc = "Flash" },
      { "<leader>mm", run("monitor"), desc = "Monitor" },
      { "<leader>mF", run("flash_monitor"), desc = "Flash + Monitor" },
      { "<leader>mc", run("clean"), desc = "Clean" },
      { "<leader>mg", run("compiledb"), desc = "Gen compile_commands.json" },
      { "<leader>mM", run("menuconfig"), desc = "menuconfig" },
      { "<leader>mi", "<cmd>IdfEnv<cr>", desc = "ESP-IDF env (get_idf)" },
    },
    init = function()
      vim.api.nvim_create_user_command("IdfEnv", function(o) idf_env(o.args) end, {
        nargs = "?",
        complete = idf_versions,
        desc = "Activate ESP-IDF (EIM) in this nvim, like get_idf",
      })

      -- PlatformIO: auto-generate compile_commands.json if missing (else clangd can't find Arduino.h)
      local generating = {}
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "c", "cpp" },
        callback = function()
          local kind, root = detect()
          if kind ~= "pio" or generating[root] or vim.uv.fs_stat(root .. "/compile_commands.json") then
            return
          end
          generating[root] = true
          vim.notify("pio: generating compile_commands.json ...")
          vim.system({ pio, "run", "-t", "compiledb" }, { cwd = root }, function(r)
            vim.schedule(function()
              generating[root] = nil
              if r.code == 0 then
                vim.notify("pio: compile_commands.json ready")
                pcall(vim.cmd, "LspRestart clangd")
              else
                vim.notify("pio compiledb failed:\n" .. (r.stderr or ""), vim.log.levels.ERROR)
              end
            end)
          end)
        end,
      })

      vim.filetype.add({
        extension = { overlay = "dts", keymap = "dts" },
        filename = { ["prj.conf"] = "kconfig", ["sdkconfig"] = "kconfig", ["sdkconfig.defaults"] = "kconfig" },
      })
    end,
  },
}
