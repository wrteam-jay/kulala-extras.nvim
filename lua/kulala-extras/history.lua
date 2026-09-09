local config = require("kulala-extras.config")

local M = {}

--- Derives a stable key for a request so history entries group correctly.
--- Scoped by the `.http` file too (`response.file`), not just method+url -
--- two different projects hitting the same URL (e.g. a shared local dev
--- health-check endpoint) would otherwise share one history file.
---
--- Identity is the request's *name* (kulala always assigns one - the
--- "### NAME" comment, or an auto-generated "REQUEST_NNN" when there
--- isn't one), not method+url. A request's URL is often edited between
--- runs (swapping an id, a query param, a page number) while it's still
--- "the same request" to the user - keying on url would split those
--- into separate histories that never see each other, breaking
--- CompareHere right when it's most useful (comparing before/after an
--- edit). This also matches how virtual_text's marker placement already
--- groups by name, not url - see find_parsed_request().
--- @param response table full response record, see kulala's
---   lua/kulala/cmd/init.lua (response.url/.method/.name/.file)
--- @return string
function M.key_for(response)
  local name = response.name or ""
  -- fnamemodify(:p) so callers computing this from a buffer name
  -- (vim.api.nvim_buf_get_name) and kulala's own response.file always
  -- normalize to the same absolute path, even if one is unresolved
  -- relative to a symlinked directory (e.g. macOS /tmp -> /private/tmp)
  local file = response.file and response.file ~= "" and vim.fn.fnamemodify(response.file, ":p") or ""
  -- hash the file path rather than inlining it - full absolute paths would
  -- make history filenames unreasonably long.
  local file_hash = vim.fn.sha256(file):sub(1, 8)

  if name ~= "" then
    return file_hash .. "_" .. name:gsub("[^%w]", "_")
  end

  -- name should always be present (kulala auto-generates one), but fall
  -- back to method+url if it's ever genuinely missing, so two truly
  -- unnamed/unidentifiable requests don't collide into one history
  local url = response.url or "unknown-url"
  local method = response.method or "GET"
  return file_hash .. "_" .. (method .. "_" .. url):gsub("[^%w]", "_")
end

--- @param key string
--- @return string
local function history_file(key)
  return config.options.history_dir .. "/" .. key .. ".json"
end

--- @param key string
--- @return table[]
local function read_history(key)
  local file = history_file(key)
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local ok, decoded = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(file), "\n"))
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

--- @param key string
--- @param entries table[]
local function write_history(key, entries)
  vim.fn.writefile({ vim.fn.json_encode(entries) }, history_file(key))
end

function M.setup()
  -- history_dir is created in config.setup(); nothing else to initialize yet.
end

--- Records one response into its request's history file.
--- @param payload table the `after_request` callback argument, shaped
---   `{ headers, body, response }` - see kulala's lua/kulala/api/init.lua
---   `M.trigger()`. `response` is the full record from
---   lua/kulala/cmd/init.lua: `response_code` is the HTTP status (`status`
---   is a success boolean, `code` is curl's own exit code - not the same
---   thing), `headers_tbl` is the parsed header table, `json` is the
---   parsed body when it's JSON.
--- @return string key, table entry the key this response was filed under,
---   and the entry that was recorded (both handy for callers like
---   virtual_text that need to render right after recording)
function M.record(payload)
  local response = payload.response or payload
  local key = M.key_for(response)
  local entries = read_history(key)

  local entry = {
    timestamp = os.time(),
    url = response.url,
    method = response.method,
    status = response.response_code,
    success = response.status,
    duration = response.duration,
    headers = response.headers_tbl or response.headers,
    body = response.body,
    json = response.json,
    buf = response.buf,
    line = response.line,
    name = response.name,
    file = response.file,
    -- the complete, unmodified response - kept alongside the curated
    -- fields above so it can be handed straight back to kulala's own UI
    -- (kulala.ui.open_default_view() reads a "Response"-shaped table with
    -- many more fields than kulala-extras itself uses, e.g. stats,
    -- _kulala_verbose_trace, request.*) - see virtual_text.open_in_kulala_ui()
    raw = response,
  }
  table.insert(entries, 1, entry)

  while #entries > config.options.max_history_per_request do
    table.remove(entries)
  end

  write_history(key, entries)
  return key, entry
end

--- @param key string
--- @return table[]
function M.get(key)
  return read_history(key)
end

--- @return string[]
function M.list_keys()
  local keys = {}
  for _, path in ipairs(vim.fn.glob(config.options.history_dir .. "/*.json", true, true)) do
    table.insert(keys, vim.fn.fnamemodify(path, ":t:r"))
  end
  return keys
end

--- Deletes one request's history file.
--- @param key string
function M.clear(key)
  local file = history_file(key)
  if vim.fn.filereadable(file) == 1 then
    vim.fn.delete(file)
  end
end

--- Deletes all recorded history, every key.
--- @return integer count of files removed
function M.clear_all()
  local n = 0
  for _, path in ipairs(vim.fn.glob(config.options.history_dir .. "/*.json", true, true)) do
    vim.fn.delete(path)
    n = n + 1
  end
  return n
end

return M
