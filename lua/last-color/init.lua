local uv = vim.loop
local cache_file = string.format('%s/last-color', vim.fn.stdpath('data'))

local M = {}

local open_cache_file = function(mode)
  -- 438(10) == 666(8) [owner/group/others can read/write]
  local flags = 438
  return uv.fs_open(cache_file, mode, flags)
end

local split_string = function(input, delimiter)
  local result = {}
  for part in string.gmatch(input, "([^" .. delimiter .. "]+)") do
    table.insert(result, part)
  end
  return result
end

local read_cache_file = function()
  local fd, err_name, err_msg = open_cache_file('r')
  if not fd then
    if err_name == 'ENOENT' then
      -- cache never written: ok, :colorscheme never executed
      return nil
    end
    error(string.format('%s: %s', err_name, err_msg))
  end

  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, -1))
  assert(uv.fs_close(fd))

  local split = split_string(tostring(data), "\n")
  if #split == 1 then
    local colorscheme = split[1]
    return colorscheme, nil
  elseif #split == 2 then
    local colorscheme = split[1]
    local background = split[2]
    return colorscheme, background
  else
    return nil, nil
  end
end

local write_cache_file = function(colorscheme)
  local fd = assert(open_cache_file('w'))
  assert(uv.fs_write(fd, string.format('%s\n%s\n', colorscheme, vim.o.background), -1))
  assert(uv.fs_close(fd))
end

--- Read the cached colorscheme from disk.
--- @return string|nil, string|nil colorscheme_background
M.recall = function()
  local ok, theme, background = pcall(read_cache_file)
  if not ok then
    return nil, nil
  else
    return theme, background
  end
end

--- Creates the autocommand which saves the last ':colorscheme' to disk, along
--- with the Ex command 'LastColor'. This is automatically called when the
--- plugin is loaded.
M.setup = function()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('last-color', { clear = true }),
    pattern = '*',
    desc = 'Cache colorscheme name to disk on change',
    callback = function(info)
      local new_scheme = info.match
      local valid_schemes = vim.fn.getcompletion('', 'color')
      -- fix for #2
      if not vim.tbl_contains(valid_schemes, new_scheme) then
        return nil
      end

      local ok, result = pcall(write_cache_file, new_scheme)
      if not ok then
        vim.api.nvim_err_writeln(string.format('cannot write to cache file: %s', result))
        -- delete the autocommand to prevent further error notifications
        return true
      end
    end,
  })

  vim.api.nvim_create_user_command('LastColor', function(_)
    print(M.recall())
  end, { desc = 'Prints the cached colorscheme' })
end

return M
