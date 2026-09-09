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

  local group = vim.api.nvim_create_augroup("KulalaExtrasHistory", { clear = true })

  -- reopening a .http/.rest file should show its already-persisted
  -- history immediately, not only after rerunning something this session
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "http", "rest" },
    callback = function(args)
      vim.wo.signcolumn = "yes" -- otherwise the "which request is active" sign has no gutter to draw in
      virtual_text.render_buffer(args.buf)
      virtual_text.update_active_sign(args.buf)

      -- keep the "▶" active-request sign in sync with the cursor - which
      -- request kulala-extras' keymaps (CompareHere/OpenHere/ClearHistoryHere)
      -- will act on should always be visible, not inferred. Buffer-local
      -- (rather than a filename-pattern match) so it only ever fires for
      -- buffers actually filetype=http/rest, however they got that way.
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        buffer = args.buf,
        callback = function()
          virtual_text.update_active_sign(args.buf)
        end,
      })
    end,
  })
end

M.history = history
M.compare = require("kulala-extras.compare")
M.virtual_text = virtual_text

return M
