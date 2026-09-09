local config = require("kulala-extras.config")

local M = {}

--- Derives a stable key for a request so history entries group correctly.
--- @param response table full response record, see kulala's
---   lua/kulala/cmd/init.lua (response.url/.method/.name)
--- @return string
function M.key_for(response)
  local url = response.url or "unknown-url"
  local method = response.method or "GET"
  return (method .. " " .. url):gsub("[^%w]", "_")
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

return M
