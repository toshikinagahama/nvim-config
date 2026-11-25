-- Build and run the current C / C++ file (or the CMake project) in a terminal split.
--   <localleader>r  build + run      <localleader>b  build only
-- Single file: gcc/g++ with warnings and debug info, binary in build/<name>
-- If a CMakeLists.txt is found upward: cmake -B build && cmake --build build
local M = {}

local function root_cmake(file)
  local found = vim.fs.find("CMakeLists.txt", { upward = true, path = vim.fs.dirname(file) })[1]
  return found and vim.fs.dirname(found) or nil
end

local function term(cmd, cwd)
  vim.cmd("botright 15split")
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  vim.cmd("startinsert")
end

function M.cmd(run)
  vim.cmd("silent! write")
  local file = vim.api.nvim_buf_get_name(0)
  local root = root_cmake(file)
  if root then
    local cmd = "cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build -j"
    if run then
      cmd = cmd .. " && echo '--- built; run your target from build/ ---'"
    end
    return cmd, root
  end
  local dir = vim.fs.dirname(file)
  local name = vim.fn.fnamemodify(file, ":t:r")
  local is_cpp = vim.bo.filetype == "cpp"
  local cc = is_cpp and "g++ -std=c++20" or "gcc -std=c17"
  local out = "build/" .. name
  local cmd = string.format("mkdir -p build && %s -Wall -Wextra -g %s -o %s -lm",
    cc, vim.fn.shellescape(vim.fn.fnamemodify(file, ":t")), vim.fn.shellescape(out))
  if run then
    cmd = cmd .. " && ./" .. vim.fn.shellescape(out)
  end
  return cmd, dir
end

function M.setup_buffer()
  local map = function(lhs, run, desc)
    vim.keymap.set("n", lhs, function()
      local cmd, cwd = M.cmd(run)
      term(cmd, cwd)
    end, { buffer = true, desc = desc })
  end
  map("<localleader>r", true, "C/C++: build and run")
  map("<localleader>b", false, "C/C++: build only")
end

return M
