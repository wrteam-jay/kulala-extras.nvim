local history = require("kulala-extras.history")

local M = {}

--- Body only - headers (cf-ray, age, date, nel, reporting-endpoints, etc.)
--- are dynamic on every single request by design and drown out the
--- actual signal: did the response body change. Status/timestamp show in
--- the buffer name (tab/title bar) instead of the diffed content itself.
--- @param entry table history entry, see history.record()
--- @return string[] lines, boolean is_json
function M.format_entry(entry)
  -- kulala's `body` is already the response as the server sent it (with
  -- its own formatting/indentation intact) - diff that directly rather
  -- than re-serializing `json`, which would just show formatting noise.
  local is_json = entry.json ~= nil
  local body = entry.body or ""
  return vim.split(body, "\n"), is_json
end

--- @param entry table history entry, see history.record()
--- @return string a short label for the buffer name / tab title
local function entry_label(entry)
  return ("%s (status %s)"):format(os.date("%Y-%m-%d %H:%M:%S", entry.timestamp), tostring(entry.status))
end

--- @param lines string[]
--- @param is_json boolean
--- @param name string buffer name, shown in the tab/window title
--- @return integer bufnr
local function make_diff_buf(lines, is_json, name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = is_json and "json" or "text"
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

--- @return integer count of diff hunks between two entries' bodies
local function count_diff_hunks(lines_a, lines_b)
  local diff = vim.diff(table.concat(lines_a, "\n") .. "\n", table.concat(lines_b, "\n") .. "\n", {
    result_type = "indices",
    algorithm = "histogram",
  })
  return diff and #diff or 0
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

  -- index_a/index_b prefix keeps buffer names unique even when two
  -- entries were recorded in the same second (entry_label()'s timestamp
  -- is only second-precision) - nvim_buf_set_name errors on a duplicate
  -- name, which silently dropped the second buffer's name entirely
  local lines_a, json_a = M.format_entry(a)
  local lines_b, json_b = M.format_entry(b)
  local buf_a = make_diff_buf(lines_a, json_a, ("kulala-extras://%d %s"):format(index_a, entry_label(a)))
  local buf_b = make_diff_buf(lines_b, json_b, ("kulala-extras://%d %s"):format(index_b, entry_label(b)))

  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, buf_a)
  vim.opt_local.diffopt:append({ "iwhite", "linematch:60" })
  vim.cmd("diffthis")
  vim.cmd("normal! zR") -- diffthis folds unchanged regions by default (foldmethod=diff) - open them, these bodies are short enough that folding just adds a step
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf_b)
  vim.opt_local.diffopt:append({ "iwhite", "linematch:60" })
  vim.cmd("diffthis")
  vim.cmd("normal! zR")

  local hunks = count_diff_hunks(lines_a, lines_b)
  vim.notify(
    ("kulala-extras: %d difference%s between the two responses"):format(hunks, hunks == 1 and "" or "s"),
    vim.log.levels.INFO
  )
end

--- Opens a single history entry in a vertical split beside the current
--- window - for "just show me this one", not a diff.
--- @param key string
--- @param index integer 1-based index into history.get(key), newest first
function M.open_single(key, index)
  local entries = history.get(key)
  local entry = entries[index]
  if not entry then
    vim.notify("kulala-extras: no such history entry", vim.log.levels.WARN)
    return
  end

  local lines, is_json = M.format_entry(entry)
  local buf = make_diff_buf(lines, is_json, ("kulala-extras://%d %s"):format(index, entry_label(entry)))
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
end

--- Diffs the two most recent responses for a request - the common case,
--- skipping the "which entries" picker entirely.
--- @param key string
function M.diff_latest(key)
  local entries = history.get(key)
  if #entries < 2 then
    vim.notify("kulala-extras: need at least 2 runs of this request to compare", vim.log.levels.WARN)
    return
  end
  M.diff(key, 1, 2)
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
