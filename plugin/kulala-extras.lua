if vim.g.loaded_kulala_extras then
  return
end
vim.g.loaded_kulala_extras = true

vim.api.nvim_create_user_command("KulalaExtrasCompare", function()
  require("kulala-extras.compare").pick_and_diff()
end, { desc = "Compare two past responses for a request (full picker)" })

vim.api.nvim_create_user_command("KulalaExtrasCompareHere", function()
  require("kulala-extras.virtual_text").compare_here()
end, { desc = "One-step: diff the two most recent responses for the request under the cursor" })

vim.api.nvim_create_user_command("KulalaExtrasOpenHere", function()
  require("kulala-extras.virtual_text").open_here()
end, { desc = "Browse past responses for the request under the cursor (live preview), open the selected one in kulala's own UI" })

vim.api.nvim_create_user_command("KulalaExtrasClearHistoryHere", function()
  require("kulala-extras.virtual_text").clear_here()
end, { desc = "Clear history for the request under the cursor" })

vim.api.nvim_create_user_command("KulalaExtrasClearHistory", function()
  local choice = vim.fn.confirm("Clear ALL kulala-extras history, every request?", "&Yes\n&No", 2)
  if choice == 1 then
    require("kulala-extras.virtual_text").clear_all()
  end
end, { desc = "Clear all recorded history, every request" })

-- curl-to-.http import is handled by kulala.nvim itself (require("kulala").from_curl()) -
-- no need to duplicate that parser here.

vim.api.nvim_create_user_command("KulalaExtrasDebugPayload", function()
  local ok, kulala_api = pcall(require, "kulala.api")
  if not ok then
    vim.notify("kulala-extras: kulala.nvim not found", vim.log.levels.ERROR)
    return
  end
  kulala_api.on("after_request", function(payload)
    vim.notify(vim.inspect(payload), vim.log.levels.INFO)
  end)
  vim.notify("kulala-extras: run a request now, its raw after_request payload will print", vim.log.levels.INFO)
end, { desc = "One-shot: print the raw after_request payload for the next request run" })
