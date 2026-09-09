local config = require("kulala-extras.config")
local history = require("kulala-extras.history")

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
    history.record(payload)
  end)
end

M.history = history
M.compare = require("kulala-extras.compare")

return M
