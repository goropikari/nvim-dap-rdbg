# nvim-dap-rdbg

[mfussenegger/nvim-dap][1] plugin for ruby

## Installation

[`lazy.nvim`][2]

```lua
{
  'goropikari/nvim-dap-rdbg',
  dependencies = {
    'mfussenegger/nvim-dap',
    'nvim-lua/plenary.nvim',
  },
  opts = {
    rdbg = {
      path = 'rdbg',
      use_bundler = false,
    },
    configurations = {},
  },
  ft = { 'ruby' },
}
```

## Setup development environment for this plugin

```bash
npm install -g @devcontainers/cli
devcontainer up --workspace-folder=.
devcontainer exec --workspace-folder=. bash

nvim
```

## Alternatives

- [suketa/nvim-dap-ruby][3]


[1]: https://github.com/mfussenegger/nvim-dap
[2]: https://github.com/folke/lazy.nvim
[3]: https://github.com/suketa/nvim-dap-ruby
