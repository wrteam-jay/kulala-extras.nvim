# kulala-extras.nvim

Adds history, compare, and an active-request sign column to
[kulala.nvim](https://github.com/mistweaverco/kulala.nvim).

Uses only kulala's public `after_request` hook. No monkeypatching, no
forked internals.

## Features

- **History**. Every response is recorded automatically, grouped by
  request.
- **Inline markers**. The last few runs show as virtual text under
  each request. History shows up on reopening a file too, not only
  after a fresh run.
- **Sign column**. A dim `│` marks a request that has history. A `▶`
  tracks your cursor. It shows which request will run next, and which
  one the `*Here` commands act on.
- **Compare**. Diff two response **bodies** in a native diff split.
  Word-level highlighting, a diff count, and JSON syntax highlighting.
  Headers are left out on purpose. Things like `date` or `cf-ray`
  change on every request and would drown out real differences.
- **Scoped per file**. Two projects that hit the same URL never mix
  history.
- **Real kulala UI**. Opening an entry shows it in kulala's own
  response window (Body/Headers/Verbose/Report). It is not a
  lookalike.

## Requirements

- Neovim 0.10 or newer
- [kulala.nvim](https://github.com/mistweaverco/kulala.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim), optional. Adds a
  live preview to `OpenHere`. Without it, `OpenHere` shows a plain
  list.

## Installation

```lua
-- lazy.nvim
{
  "wrteam-jay/kulala-extras.nvim",
  dependencies = { "mistweaverco/kulala.nvim" },
  opts = {},
}
```

## Setup

```lua
require("kulala-extras").setup({
  -- history_dir = vim.fn.stdpath("data") .. "/kulala-extras/history",
  -- max_history_per_request = 50,
})
```

## Commands

| Command                         | Does                                            |
| --------------------------------- | -------------------------------------------------- |
| `:KulalaExtrasCompareHere`      | Diffs the 2 latest responses for the cursor's request |
| `:KulalaExtrasOpenHere`         | Browses history with a preview, opens in kulala's UI |
| `:KulalaExtrasCompare`          | Full picker: any request, any two responses     |
| `:KulalaExtrasClearHistoryHere` | Clears history for the cursor's request          |
| `:KulalaExtrasClearHistory`     | Clears all history. Asks for confirmation first  |
| `:KulalaExtrasDebugPayload`     | Prints the raw payload of the next response       |

There are no default keymaps. Only commands.

```lua
-- suggested lazy.nvim keys. Check your kulala.nvim config first:
-- global_keymaps already claims most of <leader>R.
keys = {
  { "<leader>Rh", "<cmd>KulalaExtrasCompareHere<cr>", desc = "Compare latest 2 (here)" },
  { "<leader>Rd", "<cmd>KulalaExtrasCompare<cr>", desc = "Compare (full picker)" },
  { "<leader>Rl", "<cmd>KulalaExtrasOpenHere<cr>", desc = "Open a past response (here)" },
  { "<leader>Rk", "<cmd>KulalaExtrasClearHistoryHere<cr>", desc = "Clear history (here)" },
},
```

## Privacy

- History is stored as **plain, unencrypted JSON**. Default location:
  `stdpath("data")/kulala-extras/history/`. Set `history_dir` to
  change it.
- Nothing leaves your machine.
- Each entry stores the full raw response. This includes curl's
  verbose trace.
- The verbose trace includes your request headers. `Authorization` is
  included, in plain text.
- If your `.http` files send real bearer tokens or API keys, those
  tokens go to disk on every run.
- Run `:KulalaExtrasClearHistory` to wipe stored history.

## Performance

- Kulala's parser shells out to `kulala-core`. Each call spawns a
  subprocess.
- This plugin parses a buffer once per event: file open, save, or
  completed request. It reuses that one parse for every history key
  and cursor lookup.
- An earlier version parsed once per history key. That turned file-open
  into a multi-second wait. This is fixed now.
- Every parse runs through `vim.schedule()`. The buffer displays first,
  the parse runs a moment later. The parse itself still blocks the
  editor briefly when it runs, but never on file-open.

## Fragility

- `OpenHere` writes into `kulala.db`'s live response table to show
  kulala's own UI. This is not a published API.
- The write is append-only. It never changes or removes an existing
  entry. A real request run afterwards is unaffected.
- A future kulala.nvim update could change that table's shape and
  break this silently.
- If that happens, `OpenHere` falls back to a plain view. No crash.
- Entries recorded before this feature existed use the same fallback.

## Status

Early, personal project. No automated tests yet.

Field mappings and the `kulala.db` write above were checked against
real requests, not just kulala's docs. If kulala's payload shape ever
changes, run `:KulalaExtrasDebugPayload` to see the current shape.

## License

MIT
