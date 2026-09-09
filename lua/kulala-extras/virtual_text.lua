local history = require("kulala-extras.history")
local compare = require("kulala-extras.compare")

local M = {}

local ns = vim.api.nvim_create_namespace("kulala_extras_history")
local ns_signs = vim.api.nvim_create_namespace("kulala_extras_signs")

--- How many recent runs to show inline under a request.
local MAX_SHOWN = 5

--- registry[bufnr][end_line0] = { key, extmark_id, start_line0, sign_id }
--- `start_line0`/`end_line0` are 0-indexed, bracketing the request block
--- (`<method> <url>` line through its last header line). `sign_id` is the
--- dim "has history" gutter marker at start_line0 - see render().
local registry = {}

--- active[bufnr] = { key, extmark_id } - the single highlighted ">" sign
--- showing which request kulala-extras' keymaps currently target, kept in
--- sync with the cursor by update_active_sign().
local active = {}

vim.api.nvim_set_hl(0, "KulalaExtrasHistorySign", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "KulalaExtrasActiveSign", { link = "DiagnosticOk", default = true })

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
--- @return integer|nil start_line0, integer|nil end_line0 both 0-indexed
local function find_request_lines(bufnr, method, url)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, nil
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
    return nil, nil
  end

  local end_line = start_line
  for i = start_line + 1, #lines do
    local line = lines[i]
    if line == "" or line:match("^%s*###") or line:match("^%s*GET%s") or line:match("^%s*POST%s") then
      break
    end
    end_line = i
  end
  return start_line - 1, end_line - 1 -- 0-indexed
end

--- Removes any extmark previously registered for `key` in `bufnr`,
--- wherever it currently sits (the request block may have moved).
--- @param bufnr integer
--- @param key string
local function clear_registered(bufnr, key)
  if not registry[bufnr] then
    return
  end
  for line0, data in pairs(registry[bufnr]) do
    if data.key == key then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, data.extmark_id)
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, data.sign_id)
      registry[bufnr][line0] = nil
    end
  end
end

--- Renders (or re-renders) the history line under one request.
--- @param bufnr integer
--- @param key string
--- @param method string
--- @param url string
function M.render(bufnr, key, method, url)
  local start_line0, end_line0 = find_request_lines(bufnr, method, url)
  if not end_line0 then
    -- request text not found (buffer edited/request removed) - drop the
    -- stale marker rather than leaving it pointing at wrong content
    clear_registered(bufnr, key)
    return
  end

  clear_registered(bufnr, key)

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

  -- dim gutter marker on the request line itself: "this request has
  -- recorded history" - independent of whether the cursor is on it, see
  -- update_active_sign() for the highlighted "you are here" indicator
  local sign_id = vim.api.nvim_buf_set_extmark(bufnr, ns_signs, start_line0, 0, {
    sign_text = "│",
    sign_hl_group = "KulalaExtrasHistorySign",
  })

  registry[bufnr] = registry[bufnr] or {}
  registry[bufnr][end_line0] =
    { key = key, extmark_id = extmark_id, start_line0 = start_line0, sign_id = sign_id }
end

--- Moves the highlighted ">" gutter sign to whichever request the cursor
--- currently resolves to - the visual answer to "which request will
--- :KulalaExtrasCompareHere / OpenHere / ClearHistoryHere act on". Only
--- touches the sign when the resolved request actually changed, so this
--- is cheap enough to call on every CursorMoved.
--- @param bufnr integer
function M.update_active_sign(bufnr)
  local key = M.key_at_cursor(bufnr)
  local current = active[bufnr]

  if current and current.key == key then
    return -- unchanged, nothing to redraw
  end
  if current then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, current.extmark_id)
    active[bufnr] = nil
  end
  if not key then
    return
  end

  local data = registry[bufnr] and registry[bufnr][M.end_line_for_key(bufnr, key)]
  if not data then
    return
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_signs, data.start_line0, 0, {
    sign_text = "▶",
    sign_hl_group = "KulalaExtrasActiveSign",
  })
  active[bufnr] = { key = key, extmark_id = extmark_id }
end

--- @param bufnr integer
--- @param key string
--- @return integer|nil end_line0 the registry key (end line) for `key`, if any
function M.end_line_for_key(bufnr, key)
  for end_line0, data in pairs(registry[bufnr] or {}) do
    if data.key == key then
      return end_line0
    end
  end
  return nil
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

--- Renders every request in `bufnr` that already has persisted history,
--- even if nothing has been run yet this session - otherwise reopening a
--- `.http` file shows no markers until you rerun something.
--- @param bufnr integer
function M.render_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  for _, key in ipairs(history.list_keys()) do
    local entries = history.get(key)
    local latest = entries[1]
    if latest and latest.file == buf_name and latest.method and latest.url then
      M.render(bufnr, key, latest.method, latest.url)
    end
  end
end

--- Finds the history key for the request block the cursor is currently
--- inside: the block whose start line is at-or-before the cursor, closest
--- among those. A cursor above every request resolves to nothing.
--- @param bufnr integer
--- @return string|nil key
function M.key_at_cursor(bufnr)
  local lines = registry[bufnr]
  if not lines then
    return nil
  end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local best_start, best_key = nil, nil
  for _, data in pairs(lines) do
    if data.start_line0 <= cursor_line and (best_start == nil or data.start_line0 > best_start) then
      best_start, best_key = data.start_line0, data.key
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

--- Clears history + virtual text for the request under the cursor.
function M.clear_here()
  local bufnr = vim.api.nvim_get_current_buf()
  local key = M.key_at_cursor(bufnr)
  if not key then
    vim.notify("kulala-extras: no recorded history for a request at/above the cursor", vim.log.levels.WARN)
    return
  end
  clear_registered(bufnr, key)
  if active[bufnr] and active[bufnr].key == key then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, active[bufnr].extmark_id)
    active[bufnr] = nil
  end
  history.clear(key)
  vim.notify("kulala-extras: cleared history for this request", vim.log.levels.INFO)
end

--- Clears all history + virtual text, every request, every buffer.
function M.clear_all()
  for bufnr, lines in pairs(registry) do
    for _, data in pairs(lines) do
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, data.extmark_id)
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, data.sign_id)
    end
  end
  for bufnr, data in pairs(active) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, data.extmark_id)
  end
  registry = {}
  active = {}
  local n = history.clear_all()
  vim.notify(("kulala-extras: cleared %d history file(s)"):format(n), vim.log.levels.INFO)
end

return M
