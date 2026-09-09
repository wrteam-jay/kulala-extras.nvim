local history = require("kulala-extras.history")
local compare = require("kulala-extras.compare")

local M = {}

local ns = vim.api.nvim_create_namespace("kulala_extras_history")

--- How many recent runs to show inline under a request.
local MAX_SHOWN = 5

--- registry[bufnr][line] = { key = string, extmark_id = integer }
--- `line` is 0-indexed: the last line of the request block, where the
--- history virt_lines are attached (see find_request_end_line()).
local registry = {}

--- @param entry table history entry, see history.record()
--- @return string
local function label(entry)
  local time = os.date("%H:%M:%S", entry.timestamp)
  local ms = entry.duration and (" %.2fms"):format(entry.duration / 1e6) or ""
  return ("<> %s [%s]%s"):format(time, tostring(entry.status), ms)
end

--- kulala's `response.line` is not a reliable absolute buffer line (it's
--- consistently 1 regardless of where the request actually sits in the
--- file), so find the request's line range by searching the buffer text
--- directly: the line with `<method> <url>`, then forward to the last
--- non-blank line before the next request separator/blank line.
--- @param bufnr integer
--- @param method string
--- @param url string
--- @return integer|nil end_line0 0-indexed line to attach virt_lines below
local function find_request_end_line(bufnr, method, url)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local pattern = "^%s*" .. vim.pesc(method) .. "%s+" .. vim.pesc(url)

  local start_line = nil
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      start_line = i
      break
    end
  end
  if not start_line then
    return nil
  end

  local end_line = start_line
  for i = start_line + 1, #lines do
    local line = lines[i]
    if line == "" or line:match("^%s*###") or line:match("^%s*GET%s") or line:match("^%s*POST%s") then
      break
    end
    end_line = i
  end
  return end_line - 1 -- 0-indexed
end

--- Renders (or re-renders) the history line under one request.
--- @param bufnr integer
--- @param key string
--- @param method string
--- @param url string
function M.render(bufnr, key, method, url)
  local end_line0 = find_request_end_line(bufnr, method, url)
  if not end_line0 then
    return
  end

  registry[bufnr] = registry[bufnr] or {}
  -- clear any extmark previously registered for this key in this buffer,
  -- wherever it was (the request block may have moved)
  for line0, data in pairs(registry[bufnr]) do
    if data.key == key then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, data.extmark_id)
      registry[bufnr][line0] = nil
    end
  end

  local entries = history.get(key)
  if #entries == 0 then
    return
  end

  local virt_lines = {}
  for i = 1, math.min(MAX_SHOWN, #entries) do
    table.insert(virt_lines, { { "  " .. label(entries[i]), "Comment" } })
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, end_line0, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })

  registry[bufnr][end_line0] = { key = key, extmark_id = extmark_id }
end

--- Called from the after_request hook once a response has been recorded.
--- @param key string
--- @param entry table the just-recorded entry, see history.record()
function M.on_record(key, entry)
  if not (entry.buf and entry.method and entry.url) then
    return
  end
  M.render(entry.buf, key, entry.method, entry.url)
end

--- Finds the history key registered at or above the cursor in the current
--- buffer - i.e. the request the cursor is currently "inside".
--- @param bufnr integer
--- @return string|nil key
function M.key_at_cursor(bufnr)
  local lines = registry[bufnr]
  if not lines then
    return nil
  end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local best_line, best_key = nil, nil
  for line0, data in pairs(lines) do
    -- the request whose block ends closest to (at or after) the cursor,
    -- or the closest one above it if the cursor is past every block end
    if best_line == nil or math.abs(line0 - cursor_line) < math.abs(best_line - cursor_line) then
      best_line, best_key = line0, data.key
    end
  end
  return best_key
end

--- One-step compare: diffs the two most recent runs of the request under
--- the cursor, no picker needed.
function M.compare_here()
  local key = M.key_at_cursor(vim.api.nvim_get_current_buf())
  if not key then
    vim.notify("kulala-extras: no recorded history for a request at/above the cursor", vim.log.levels.WARN)
    return
  end
  compare.diff_latest(key)
end

--- Opens a single history entry (not a diff) in a vertical split - the
--- "pick one, view it" flow, since virt_lines aren't cursor-addressable.
function M.open_here()
  local key = M.key_at_cursor(vim.api.nvim_get_current_buf())
  if not key then
    vim.notify("kulala-extras: no recorded history for a request at/above the cursor", vim.log.levels.WARN)
    return
  end

  local entries = history.get(key)
  if #entries == 0 then
    vim.notify("kulala-extras: no history entries for this request", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for i, entry in ipairs(entries) do
    labels[i] = label(entry)
  end

  vim.ui.select(labels, { prompt = "Open response:" }, function(_, idx)
    if not idx then
      return
    end
    compare.open_single(key, idx)
  end)
end

return M
