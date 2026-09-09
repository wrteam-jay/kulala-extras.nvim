local config = require("kulala-extras.config")

local M = {}

--- Derives a stable key for a request so history entries group correctly.
--- Falls back gracefully across kulala response shapes since the exact
--- field names are not pinned in kulala's docs as of this writing.
--- @param response table
--- @return string
local function request_key(response)
  local url = response.url or (response.request and response.request.url) or "unknown-url"
  local method = response.method or (response.request and response.request.method) or "GET"
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
--- @param response table raw response object from kulala's after_request hook
function M.record(response)
  local key = request_key(response)
  local entries = read_history(key)

  table.insert(entries, 1, {
    timestamp = os.time(),
    url = response.url or (response.request and response.request.url),
    method = response.method or (response.request and response.request.method),
    status = response.status or response.code,
    headers = response.headers,
    body = response.body,
  })

  while #entries > config.options.max_history_per_request do
    table.remove(entries)
  end

  write_history(key, entries)
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
