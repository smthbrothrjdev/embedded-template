return {
  {
    -- Kickstart already includes nvim-lspconfig, this just adds config
    'neovim/nvim-lspconfig',
    opts = function(_, opts)
      local util = require 'lspconfig.util'

      -- Kickstart uses opts.servers table for per-server config
      opts.servers = opts.servers or {}
      opts.servers.tailwindcss = {
        -- If installed via npm/pnpm/bun and available on PATH, this works
        cmd = { 'tailwindcss-language-server', '--stdio' },

        -- Attach only in Tailwind projects (prevents “random attach everywhere”)
        root_dir = util.root_pattern(
          'tailwind.config.js',
          'tailwind.config.cjs',
          'tailwind.config.mjs',
          'tailwind.config.ts',
          'postcss.config.js',
          'postcss.config.cjs',
          'postcss.config.mjs',
          'package.json'
        ),

        filetypes = {
          'html',
          'css',
          'scss',
          'javascript',
          'javascriptreact',
          'typescript',
          'typescriptreact',
          'svelte',
          'vue',
        },

        -- Keep tsserver in charge of code intelligence; Tailwind only does Tailwind
        on_attach = function(client, bufnr)
          client.server_capabilities.definitionProvider = false
          client.server_capabilities.referencesProvider = false
          client.server_capabilities.renameProvider = false
        end,

        settings = {
          tailwindCSS = {
            experimental = {
              classRegex = {
                'className%s*=%s*"([^"]*)"',
                'class%s*=%s*"([^"]*)"',
                'tw`([^`]*)`',
              },
            },
          },
        },
      }

      return opts
    end,
  },
}
