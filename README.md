# kulala-extras.nvim

Response history and side-by-side compare on top of
[kulala.nvim](https://github.com/mistweaverco/kulala.nvim) — the two
things a JetBrains-style `.http` workflow is missing in Neovim.

kulala.nvim already does the hard part: parsing `.http` files, sending
requests, and curl-paste import (`<leader>RC` / `require("kulala").from_curl()`).
This plugin only adds a thin layer on top, using kulala's public
`require("kulala.api").on("after_request", ...)` hook — no monkeypatching,
no forked internals.

## Features

- **History** — every response is recorded automatically (timestamp,
  status, headers, body), grouped per request.
- **Inline history markers** — the last few runs of a request show up as
  virtual text right under it in the buffer, JetBrains-style, no separate
  panel to open. Persisted history shows up immediately when you reopen a
  file too, not only after rerunning something.
- **Active-request sign column** — a dim `│` marks every request that has
  recorded history; a highlighted `▶` tracks the cursor to show exactly
  which request `CompareHere`/`OpenHere`/`ClearHistoryHere` will act on
  in a file with multiple requests, gitsigns-style.
- **Compare** — diff two past responses in a native Neovim diff split,
  with word-level highlighting, a difference count, and JSON syntax
  highlighting when the response was JSON. `:KulalaExtrasCompareHere`
  diffs the two latest runs of whatever request the cursor is on in one
  step; `:KulalaExtrasCompare` is the full picker for anything older.
- History is scoped per `.http`/`.rest` file, so two projects hitting the
  same URL (e.g. a shared local dev endpoint) never mix histories.

## Requirements

- Neovim >= 0.10
- [kulala.nvim](https://github.com/mistweaverco/kulala.nvim)

## Installation

<details>
<summary>lazy.nvim</summary>

```lua
{
  "your-username/kulala-extras.nvim",
  dependencies = { "mistweaverco/kulala.nvim" },
  opts = {},
}
```

</details>

## Setup

```lua
require("kulala-extras").setup({
  -- history_dir = vim.fn.stdpath("data") .. "/kulala-extras/history",
  -- max_history_per_request = 50,
})
```

## Usage

| Command                          | Does                                                       |
| ---------------------------------- | ------------------------------------------------------------ |
| `:KulalaExtrasCompareHere`       | Diff the 2 latest responses for the request under the cursor |
| `:KulalaExtrasOpenHere`          | Pick one past response for the request under the cursor, open it in a side split |
| `:KulalaExtrasCompare`           | Full picker: pick a request, then two past responses         |
| `:KulalaExtrasClearHistoryHere`  | Clear history for the request under the cursor               |
| `:KulalaExtrasClearHistory`      | Clear all recorded history, every request (asks to confirm)  |
| `:KulalaExtrasDebugPayload`      | One-shot: print the raw payload of the next response          |

History is recorded automatically once `setup()` runs — nothing to call
per request.

## Privacy

History is stored **unencrypted, in plain JSON**, under
`stdpath("data")/kulala-extras/history/` (configurable via
`history_dir`). Response bodies are saved verbatim - if an API echoes
tokens, PII, or other sensitive data back in a response, that data
persists to disk indefinitely (or until `:KulalaExtrasClearHistory`).
Nothing is sent anywhere; this is purely local, but treat that directory
the way you'd treat any other local cache of API responses.

## Status

Early / personal project, not yet published. Verified against real
requests - the `after_request` payload shape (`response.response_code`
for HTTP status, `response.status` as a success bool, `response.headers_tbl`
for structured headers) is now pinned in `lua/kulala-extras/history.lua`.

## License

MIT
