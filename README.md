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
  recorded history. A highlighted `▶` tracks the cursor across every
  request in the file (using kulala's own parser, not text matching) to
  show which one kulala would run next - and, since it's cursor-based,
  also which one `CompareHere`/`OpenHere`/`ClearHistoryHere` act on.
  gitsigns-style: always visible, never inferred.
- **Compare** — diff two past responses in a native Neovim diff split,
  with word-level highlighting, a difference count, and JSON syntax
  highlighting when the response was JSON. `:KulalaExtrasCompareHere`
  diffs the two latest runs of whatever request the cursor is on in one
  step; `:KulalaExtrasCompare` is the full picker for anything older.
- History is scoped per `.http`/`.rest` file, so two projects hitting the
  same URL (e.g. a shared local dev endpoint) never mix histories.
- **Opens in kulala's real UI, not a lookalike** — selecting a history
  entry (via `OpenHere`) appends it to kulala's own response DB and calls
  its native `open_default_view()`, so you get the exact same
  Body/Headers/Verbose/Report window a live request opens, not a
  separate view kulala-extras built itself. This writes into
  `kulala.db`'s internal `responses` table, which isn't a published API -
  see **Fragility** below.

## Requirements

- Neovim >= 0.10
- [kulala.nvim](https://github.com/mistweaverco/kulala.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim) *(optional)* - gives
  `:KulalaExtrasOpenHere` a live preview while browsing history. Without
  it, that command falls back to a plain `vim.ui.select` list (no
  preview) - nothing else in the plugin depends on it.

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
| `:KulalaExtrasOpenHere`          | Browse past responses for the request under the cursor with a live preview (status/headers/body); Enter opens the selected one in kulala's own native response window |
| `:KulalaExtrasCompare`           | Full picker: pick a request, then two past responses         |
| `:KulalaExtrasClearHistoryHere`  | Clear history for the request under the cursor               |
| `:KulalaExtrasClearHistory`      | Clear all recorded history, every request (asks to confirm)  |
| `:KulalaExtrasDebugPayload`      | One-shot: print the raw payload of the next response          |

History is recorded automatically once `setup()` runs — nothing to call
per request.

## Privacy

History is stored **unencrypted, in plain JSON**, under
`stdpath("data")/kulala-extras/history/` (configurable via
`history_dir`). Nothing is sent anywhere; this is purely local, but
treat that directory the way you'd treat any other local cache of API
responses/credentials.

**Every entry now stores the complete raw response** (`entry.raw`, added
for `open_in_kulala_ui()` - kulala's UI functions expect the full
"Response"-shaped table). This includes `_kulala_verbose_trace`, curl's
own verbose trace text - which contains **every request header sent,
`Authorization` included, in plaintext**. Before this, history only ever
stored response bodies/headers; now every recorded request's own
credentials persist to disk too, indefinitely (or until
`:KulalaExtrasClearHistory`). If your `.http` files send real bearer
tokens/API keys, they're now written to `history_dir` in the clear on
every run.

## Performance

`kulala.parser.document.get_document()` (kulala's own request parser)
shells out to the `kulala-core` binary - each call is a subprocess spawn,
not free. This plugin parses a buffer **once** per event (file open, text
change, completed request) and reuses that single parse for every history
key and for cursor lookups; the cursor-tracked `▶` sign itself does no
parsing at all; on `CursorMoved` it's a plain array scan against the
cached parse. Calling `get_document()` once per history key on file open
was an earlier bug here - it turned opening a file with a handful of
recorded requests into a multi-second wait.

Parsing is deferred a tick via `vim.schedule()` everywhere it's
triggered (file open, text change, completed request) - kulala's
document parser has no public async entry point, so the call itself
still blocks when it runs, but scheduling it means the buffer displays
and stays editable first instead of the parse stalling the triggering
event.

## Fragility

Opening a history entry writes it into `kulala.db`'s live `responses`
table and points `current_response_pos` at it, then calls
`kulala.ui.open_default_view()` - kulala's own internal state, not a
published API. Deliberately append-only (never overwrites or removes an
existing entry), so a real request run afterwards is unaffected, but a
future kulala.nvim update that changes that DB's shape could break this
silently. If it does, `open_in_kulala_ui()` falls back to
`compare.open_single()` (kulala-extras' own plain view) automatically -
worst case is a less pretty window, not a crash.

Entries recorded before this feature existed have no `raw` field and
fall back to the plain view too - only re-run requests get the full
kulala-UI treatment retroactively.

## Status

Early / personal project, not yet published. Verified against real
requests - the `after_request` payload shape (`response.response_code`
for HTTP status, `response.status` as a success bool, `response.headers_tbl`
for structured headers) is now pinned in `lua/kulala-extras/history.lua`.

## License

MIT
