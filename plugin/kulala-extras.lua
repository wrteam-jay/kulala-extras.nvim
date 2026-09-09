if vim.g.loaded_kulala_extras then
  return
end
vim.g.loaded_kulala_extras = true

vim.api.nvim_create_user_command("KulalaExtrasCompare", function()
  require("kulala-extras.compare").pick_and_diff()
end, { desc = "Compare two past responses for a request" })

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
