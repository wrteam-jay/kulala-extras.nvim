local config = require("kulala-extras.config")
local history = require("kulala-extras.history")
local virtual_text = require("kulala-extras.virtual_text")

local M = {}

--- @param opts table|nil see config.lua for available keys
function M.setup(opts)
  config.setup(opts)
  history.setup()

  local ok, kulala_api = pcall(require, "kulala.api")
  if not ok then
    vim.notify("kulala-extras: kulala.nvim not found, history will not be recorded", vim.log.levels.WARN)
    return
  end

  kulala_api.on("after_request", function(payload)
    local key, entry = history.record(payload)
    virtual_text.on_record(key, entry)
  end)
end

M.history = history
M.compare = require("kulala-extras.compare")
M.virtual_text = virtual_text

return M
