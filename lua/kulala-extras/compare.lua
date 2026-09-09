local history = require("kulala-extras.history")

local M = {}

--- @param entry table history entry, see history.record()
--- @return string[]
local function format_entry(entry)
  local lines = {
    ("# %s (status %s)"):format(os.date("%Y-%m-%d %H:%M:%S", entry.timestamp), tostring(entry.status)),
    "",
  }
  if entry.headers then
    -- kulala's headers_tbl values are lists (a header can repeat), e.g.
    -- { ["cache-control"] = { "no-cache", "private" } }
    for k, v in pairs(entry.headers) do
      local value = type(v) == "table" and table.concat(v, ", ") or tostring(v)
      table.insert(lines, ("%s: %s"):format(k, value))
    end
    table.insert(lines, "")
  end
  for _, line in ipairs(vim.split(entry.body or "", "\n")) do
    table.insert(lines, line)
  end
  return lines
end

--- Opens a vertical diff split between two history entries for the given key.
--- @param key string request key from history.list_keys()
--- @param index_a integer 1-based index into history.get(key), newest first
--- @param index_b integer
function M.diff(key, index_a, index_b)
  local entries = history.get(key)
  local a, b = entries[index_a], entries[index_b]
  if not a or not b then
    vim.notify("kulala-extras: not enough history entries to compare", vim.log.levels.WARN)
    return
  end

  local buf_a = vim.api.nvim_create_buf(false, true)
  local buf_b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf_a, 0, -1, false, format_entry(a))
  vim.api.nvim_buf_set_lines(buf_b, 0, -1, false, format_entry(b))

  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, buf_a)
  vim.cmd("diffthis")
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf_b)
  vim.cmd("diffthis")
end

--- Prompts for a request key then two entry indices via vim.ui.select/input.
function M.pick_and_diff()
  local keys = history.list_keys()
  if #keys == 0 then
    vim.notify("kulala-extras: no history recorded yet", vim.log.levels.INFO)
    return
  end

  vim.ui.select(keys, { prompt = "Compare responses for:" }, function(key)
    if not key then
      return
    end
    local entries = history.get(key)
    local labels = {}
    for i, entry in ipairs(entries) do
      labels[i] = ("[%d] %s status %s"):format(i, os.date("%H:%M:%S", entry.timestamp), tostring(entry.status))
    end

    vim.ui.select(labels, { prompt = "First response:" }, function(_, idx_a)
      if not idx_a then
        return
      end
      vim.ui.select(labels, { prompt = "Second response:" }, function(_, idx_b)
        if not idx_b then
          return
        end
        M.diff(key, idx_a, idx_b)
      end)
    end)
  end)
end

return M
