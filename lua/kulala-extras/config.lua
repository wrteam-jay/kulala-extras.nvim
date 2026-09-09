local M = {}

--- @class KulalaExtrasConfig
--- @field history_dir string directory where per-project history json is stored
--- @field max_history_per_request integer how many past runs to keep per request key
local defaults = {
  history_dir = vim.fn.stdpath("data") .. "/kulala-extras/history",
  max_history_per_request = 50,
}

M.options = vim.deepcopy(defaults)

--- @param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  vim.fn.mkdir(M.options.history_dir, "p")
end

return M
