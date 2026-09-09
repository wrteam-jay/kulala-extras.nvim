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
      vim.wo.signcolumn = "yes" -- otherwise the sign column has no gutter to draw in
      -- render_buffer() parses once and populates parsed_cache itself -
      -- a separate refresh_parsed() call here would be a second,
      -- redundant kulala-core subprocess spawn
      virtual_text.render_buffer(args.buf)
      virtual_text.update_active_sign(args.buf)

      -- kulala.parser.document.get_document() (used by refresh_parsed)
      -- shells out to kulala-core, so it's re-parsed on text changes/save
      -- only - never per-keystroke (TextChangedI) or per CursorMoved,
      -- both far too frequent for a subprocess call.
      vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
        group = group,
        buffer = args.buf,
        callback = function()
          virtual_text.refresh_parsed(args.buf)
          virtual_text.update_active_sign(args.buf)
        end,
      })

      -- keep the "▶" sign in sync with the cursor - cheap: just an
      -- array lookup against the cache refresh_parsed() maintains, no
      -- subprocess call, safe for every CursorMoved.
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
