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

--- active[bufnr] = { extmark_id } - the single highlighted "▶" sign
--- showing which request kulala will run next (cursor-tracked), kept in
--- sync by update_active_sign().
local active = {}

--- parsed_cache[bufnr] = requests array from kulala's own document parser.
--- kulala.parser.document.get_document() shells out to kulala-core, so
--- it's re-parsed on text changes/save (see init.lua), never on every
--- CursorMoved - that would spawn a process per cursor move.
local parsed_cache = {}

vim.api.nvim_set_hl(0, "KulalaExtrasHistorySign", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "KulalaExtrasActiveSign", { link = "DiagnosticOk", default = true })

--- @param entry table history entry, see history.record()
--- @return string
local function label(entry)
  local time = os.date("%H:%M:%S", entry.timestamp)
  local ms = entry.duration and (" %.2fms"):format(entry.duration / 1e6) or ""
  return ("<> %s [%s]%s"):format(time, tostring(entry.status), ms)
end

--- Parses `bufnr` via kulala's own document parser (one `kulala-core`
--- subprocess spawn). The single choke point every other function in
--- this module should call through, so a caller needing both the
--- rendered markers and the cursor cache from one event (on_record, in
--- particular) parses once, not twice.
--- @return table[]|nil requests
local function parse_buffer()
  local ok, document = pcall(require, "kulala.parser.document")
  if not ok then
    return nil
  end
  local parse_ok, result = pcall(document.get_document)
  return parse_ok and result or nil
end

--- Re-parses `bufnr` via kulala's own document parser and caches the
--- result for cheap (no-subprocess) cursor lookups. Call on text changes
--- or save, not on every cursor move.
--- @param bufnr integer
function M.refresh_parsed(bufnr)
  parsed_cache[bufnr] = parse_buffer()
end

--- Finds the parsed request matching a history key's name/method/url -
--- kulala's own boundaries (start_line/end_line), so this is correct even
--- when two requests share a method+url and only their name differs.
--- @param requests table[] kulala's parsed requests for one buffer
--- @param name string|nil
--- @param method string
--- @param url string
--- @return table|nil request
local function find_parsed_request(requests, name, method, url)
  if not requests then
    return nil
  end
  local fallback = nil
  for _, req in ipairs(requests) do
    if req.method == method and req.url == url then
      if name and name ~= "" and req.name == name then
        return req
      end
      fallback = fallback or req
    end
  end
  return fallback
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

--- Places the history extmark + dim gutter sign for one request, given an
--- already-parsed `req` (kulala's start_line/end_line). No parsing here -
--- callers that have already parsed the buffer (render_buffer, in
--- particular) must not re-parse per key, that's one `kulala-core`
--- subprocess spawn per key and was the entire cause of a multi-second
--- file-open regression before this was split out.
--- @param bufnr integer
--- @param key string
--- @param req table kulala's parsed request (.start_line/.end_line)
local function place_markers(bufnr, key, req)
  local start_line0, end_line0 = req.start_line - 1, req.end_line - 1

  clear_registered(bufnr, key)

  local entries = history.get(key)
  if #entries == 0 then
    return
  end

  local virt_lines = {}
  for i = 1, math.min(MAX_SHOWN, #entries) do
    table.insert(virt_lines, { { "  " .. label(entries[i]), "Comment" } })
  end
  table.insert(virt_lines, { { "", "Comment" } }) -- trailing blank line so this doesn't visually run into the next request's ###

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, end_line0, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })

  -- dim gutter marker on the request line itself: "this request has
  -- recorded history" - independent of whether the cursor is on it, see
  -- update_active_sign() for the "kulala will run this next" indicator
  local sign_id = vim.api.nvim_buf_set_extmark(bufnr, ns_signs, start_line0, 0, {
    sign_text = "│",
    sign_hl_group = "KulalaExtrasHistorySign",
  })

  registry[bufnr] = registry[bufnr] or {}
  registry[bufnr][end_line0] =
    { key = key, extmark_id = extmark_id, start_line0 = start_line0, sign_id = sign_id }
end

--- Renders (or re-renders) the history line under one request. Called
--- infrequently (once per completed request), so a fresh parse here -
--- rather than the cached one - is fine and stays accurate immediately.
--- For rendering many keys at once, see render_buffer() - it parses once
--- and reuses the result, this parses fresh every call.
--- @param bufnr integer
--- @param key string
--- @param name string|nil
--- @param method string
--- @param url string
function M.render(bufnr, key, name, method, url)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local req = find_parsed_request(parse_buffer(), name, method, url)

  if not req or not req.start_line then
    -- request text not found (buffer edited/request removed) - drop the
    -- stale marker rather than leaving it pointing at wrong content
    clear_registered(bufnr, key)
    return
  end
  place_markers(bufnr, key, req)
end

--- Called from the after_request hook once a response has been recorded.
--- Parses once and reuses it for both the rendered marker and the cursor
--- cache (see parse_buffer()) - two separate parses here would be two
--- kulala-core subprocess spawns per completed request.
--- @param key string
--- @param entry table the just-recorded entry, see history.record()
function M.on_record(key, entry)
  if not (entry.buf and entry.method and entry.url) then
    return
  end
  local requests = parse_buffer()
  parsed_cache[entry.buf] = requests

  local req = find_parsed_request(requests, entry.name, entry.method, entry.url)
  if req and req.start_line then
    place_markers(entry.buf, key, req)
  else
    clear_registered(entry.buf, key)
  end

  M.update_active_sign(entry.buf)
end

--- The request kulala would run right now, cursor-based - from the
--- cached parse, not a fresh (subprocess) one. See refresh_parsed().
---
--- Deliberately does the start_line/end_line membership check directly
--- rather than calling kulala's own `document.get_request_at()`: that
--- function mutates its `requests` argument (inserts a synthesized
--- "shared" pseudo-request at position 1 when the first request has a
--- runnable shared block) and can error internally in ways an outer
--- xpcall silently swallows, returning `{}` - it's tuned for kulala's own
--- run-flow, not safe to call out-of-band like this.
--- @param bufnr integer
--- @return table|nil request kulala's parsed request, with
---   .start_line/.end_line/.name/.method/.url
function M.request_at_cursor(bufnr)
  local requests = parsed_cache[bufnr]
  if not requests then
    return nil
  end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  for _, req in ipairs(requests) do
    if req.start_line and req.end_line and cursor_line >= req.start_line and cursor_line <= req.end_line then
      return req
    end
  end
  return nil
end

--- The history key for the request kulala would run right now - i.e.
--- what CompareHere/OpenHere/ClearHistoryHere act on. May be a request
--- with no recorded history yet (nil in that case, from history's side).
--- @param bufnr integer
--- @return string|nil key
function M.key_at_cursor(bufnr)
  local req = M.request_at_cursor(bufnr)
  if not req then
    return nil
  end
  return history.key_for({ file = vim.api.nvim_buf_get_name(bufnr), name = req.name, method = req.method, url = req.url })
end

--- Moves the highlighted "▶" gutter sign to whichever request kulala
--- would run right now (cursor-based) - every request, not only ones
--- with recorded history. Only touches the sign when the resolved
--- request's line actually changed, so this is cheap enough for
--- CursorMoved.
--- @param bufnr integer
function M.update_active_sign(bufnr)
  local req = M.request_at_cursor(bufnr)
  local current = active[bufnr]
  local start_line0 = req and (req.start_line - 1) or nil

  if current and current.start_line0 == start_line0 then
    return -- unchanged, nothing to redraw
  end
  if current then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_signs, current.extmark_id)
    active[bufnr] = nil
  end
  if not start_line0 then
    return
  end

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_signs, start_line0, 0, {
    sign_text = "▶",
    sign_hl_group = "KulalaExtrasActiveSign",
  })
  active[bufnr] = { extmark_id = extmark_id, start_line0 = start_line0 }
end

--- Renders every request in `bufnr` that already has persisted history,
--- even if nothing has been run yet this session - otherwise reopening a
--- `.http` file shows no markers until you rerun something.
---
--- Parses the buffer exactly once and reuses that for every history key
--- (and for parsed_cache, so a separate refresh_parsed() call right after
--- this would be redundant) - each parse is a `kulala-core` subprocess
--- spawn, and calling M.render() per key here previously meant one spawn
--- per key, turning file-open into a multi-second wait with more than a
--- couple of recorded requests.
--- @param bufnr integer
function M.render_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local ok, document = pcall(require, "kulala.parser.document")
  local requests = nil
  if ok then
    local parse_ok, result = pcall(document.get_document)
    requests = parse_ok and result or nil
  end
  parsed_cache[bufnr] = requests

  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  for _, key in ipairs(history.list_keys()) do
    local entries = history.get(key)
    local latest = entries[1]
    if latest and latest.file == buf_name and latest.method and latest.url then
      local req = find_parsed_request(requests, latest.name, latest.method, latest.url)
      if req and req.start_line then
        place_markers(bufnr, key, req)
      else
        clear_registered(bufnr, key)
      end
    end
  end
end

--- One-step compare: diffs the two most recent runs of the request under
--- the cursor, no picker needed.
function M.compare_here()
  local key = M.key_at_cursor(vim.api.nvim_get_current_buf())
  if not key then
    vim.notify("kulala-extras: no recorded history for the request under the cursor", vim.log.levels.WARN)
    return
  end
  compare.diff_latest(key)
end

--- Browses history entries with a live preview (status/headers/body) via
--- Snacks.picker, so you can see what a response actually was before
--- deciding to open it - arrow through, Enter opens the selected one in
--- a side split. See open_here() for the plain vim.ui.select fallback
--- when Snacks isn't installed.
--- @param key string
--- @param entries table[] history.get(key) result
local function open_with_snacks_preview(key, entries)
  local items = {}
  for i, entry in ipairs(entries) do
    local lines, is_json = compare.format_entry(entry)
    items[i] = {
      text = label(entry),
      preview = { text = table.concat(lines, "\n"), ft = is_json and "json" or nil },
    }
  end

  Snacks.picker.pick({
    source = "kulala_extras_history",
    title = "kulala-extras history",
    items = items,
    format = "text",
    preview = "preview",
    confirm = function(picker, item)
      picker:close()
      if item then
        compare.open_single(key, item.idx)
      end
    end,
  })
end

--- Opens a single history entry (not a diff) in a vertical split - the
--- "pick one, view it" flow, since virt_lines aren't cursor-addressable.
--- Uses Snacks.picker for a live preview when available (see
--- open_with_snacks_preview()), falls back to a plain vim.ui.select list
--- (no preview) otherwise - kulala-extras doesn't hard-depend on Snacks.
function M.open_here()
  local key = M.key_at_cursor(vim.api.nvim_get_current_buf())
  if not key then
    vim.notify("kulala-extras: no recorded history for the request under the cursor", vim.log.levels.WARN)
    return
  end

  local entries = history.get(key)
  if #entries == 0 then
    vim.notify("kulala-extras: no history entries for this request", vim.log.levels.INFO)
    return
  end

  local has_snacks = pcall(require, "snacks") and _G.Snacks and _G.Snacks.picker
  if has_snacks then
    return open_with_snacks_preview(key, entries)
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
    vim.notify("kulala-extras: no recorded history for the request under the cursor", vim.log.levels.WARN)
    return
  end
  clear_registered(bufnr, key)
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
