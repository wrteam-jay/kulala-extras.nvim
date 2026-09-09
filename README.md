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
- **Compare** — pick two past responses for the same request and diff them
  in a native Neovim diff split.

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

| Command                       | Does                                                |
| ------------------------------ | ---------------------------------------------------- |
| `:KulalaExtrasCompare`         | Pick a request, then two past responses, diff them   |
| `:KulalaExtrasDebugPayload`    | One-shot: print the raw payload of the next response |

History is recorded automatically once `setup()` runs — nothing to call
per request.

## Status

Early / personal project, not yet published. The exact shape of kulala's
`after_request` payload (field names for status/url/method/headers/body)
is not pinned in kulala's docs - `lua/kulala-extras/history.lua`'s
`request_key()` guesses a fallback chain. Run `:KulalaExtrasDebugPayload`
once against a real request and adjust `history.lua` if the field names
printed don't match.

## License

MIT
