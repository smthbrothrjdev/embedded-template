-- ~/.config/nvim/lua/custom/plugins/dap-embedded.lua
--
-- Key rule for cpptools (OpenDebugAD7):
-- Do NOT run "continue" inside setup/postRemoteConnect commands.
-- cpptools expects those commands to return MI ^done, but continue returns ^running.

return {
  {
    'mfussenegger/nvim-dap',
    dependencies = {
      'rcarriga/nvim-dap-ui',
      'nvim-neotest/nvim-nio',
      'theHamsta/nvim-dap-virtual-text',
    },
    config = function()
      local dap = require 'dap'
      local dapui = require 'dapui'

      local M = {}
      M.elf_path = '${workspaceFolder}/build/target/firmware.elf'
      M.gdb_host = '127.0.0.1'
      M.gdb_port = 3333

      local function notify(msg, level, title)
        vim.notify(msg, level or vim.log.levels.INFO, { title = title or 'DAP' })
      end

      local function executable_or_nil(bin)
        return (vim.fn.executable(bin) == 1) and bin or nil
      end

      local function pick_gdb()
        return executable_or_nil 'arm-none-eabi-gdb' or executable_or_nil 'gdb-multiarch' or executable_or_nil 'gdb'
      end

      local function SC(cmd)
        return { text = cmd }
      end

      local function make_target()
        vim.cmd 'wall'
        local out = vim.fn.system { 'make', '-C', 'target' }
        if vim.v.shell_error ~= 0 then
          notify(out, vim.log.levels.ERROR, 'FwBuild failed')
          return false
        end
        notify('Build OK', vim.log.levels.INFO, 'FwBuild')
        return true
      end

      local function is_openocd_listening()
        local cmd = string.format([[ss -ltnH "sport = :%d" 2>/dev/null | awk '{print $4}']], M.gdb_port)
        local out = vim.fn.system(cmd)
        if vim.v.shell_error ~= 0 then
          return true
        end
        return out:match('127%.0%.0%.1:' .. M.gdb_port) ~= nil
      end

      local function any_established_gdb_clients()
        local cmd = string.format([[ss -tnHp state established "( sport = :%d )" 2>/dev/null]], M.gdb_port)
        local out = vim.fn.system(cmd)
        if vim.v.shell_error ~= 0 then
          return false, ''
        end
        local has = out ~= nil and out:match '%S' ~= nil
        return has, out
      end

      local function ensure_prereqs()
        local gdb = pick_gdb()
        if not gdb then
          notify('No GDB found (arm-none-eabi-gdb / gdb-multiarch / gdb)', vim.log.levels.ERROR, 'DAP prereq')
          return false
        end

        local open_debug_ad7 = vim.fn.stdpath 'data' .. '/mason/bin/OpenDebugAD7'
        if vim.fn.executable(open_debug_ad7) ~= 1 then
          notify('OpenDebugAD7 missing. Install via :Mason (package: cpptools).', vim.log.levels.ERROR, 'DAP prereq')
          return false
        end

        if not is_openocd_listening() then
          notify(string.format('OpenOCD not listening on %s:%d. Start OpenOCD first.', M.gdb_host, M.gdb_port), vim.log.levels.ERROR, 'DAP prereq')
          return false
        end

        local has_estab, estab_out = any_established_gdb_clients()
        if has_estab then
          notify(
            'Port 3333 already has an established client connection.\n' .. 'Close the other client and try again.\n\n' .. estab_out,
            vim.log.levels.ERROR,
            'DAP prereq'
          )
          return false
        end

        return true
      end

      -- ============================
      -- Firmware Assembly Views (objdump)
      -- ============================

      local function resolve_workspace(path)
        return (path:gsub('${workspaceFolder}', vim.fn.getcwd()))
      end

      local function elf_path_abs()
        return vim.fn.fnamemodify(resolve_workspace(M.elf_path), ':p')
      end

      local function pick_objdump()
        return executable_or_nil 'arm-none-eabi-objdump' or executable_or_nil 'objdump' or executable_or_nil 'llvm-objdump'
      end

      local function open_asm_scratch(title)
        vim.cmd 'vnew'
        local buf = vim.api.nvim_get_current_buf()

        pcall(vim.api.nvim_buf_set_name, buf, title)

        vim.bo[buf].buftype = 'nofile'
        vim.bo[buf].bufhidden = 'wipe'
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = true
        vim.bo[buf].filetype = 'asm'

        -- Close asm window quickly
        vim.keymap.set('n', 'q', '<cmd>bd!<CR>', { buffer = buf, silent = true, nowait = true, desc = 'Close' })

        return buf
      end

      local function set_buf_text(buf, text)
        -- vim.system() callbacks run in a fast event context; scheduling avoids E5560
        if vim.in_fast_event and vim.in_fast_event() then
          vim.schedule(function()
            set_buf_text(buf, text)
          end)
          return
        end
        local lns = vim.split(text or '', '\n', { plain = true })
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lns)
        vim.bo[buf].modifiable = false
      end

      local function run_cmd(cmd, on_done)
        -- Prefer async if available (Neovim 0.10+)
        if vim.system then
          vim.system(cmd, { text = true }, function(res)
            vim.schedule(function()
              on_done(res.code or 1, res.stdout or '', res.stderr or '')
            end)
          end)
          return
        end

        -- Sync fallback
        local out = vim.fn.system(cmd)
        local code = vim.v.shell_error
        on_done(code, out or '', '')
      end

      local function objdump_cmd_full(elf)
        -- GNU objdump flags:
        --   -d   disassemble
        --   -S   intermix source (requires debug info)
        --   -l   include line numbers
        return { pick_objdump(), '-dS', '-l', '--demangle', '--wide', elf }
      end

      local function objdump_cmd_func(elf, sym)
        return { pick_objdump(), '-dS', '-l', '--demangle', '--wide', ('--disassemble=' .. sym), elf }
      end

      local function fw_asm_open(cmd, title)
        local buf = open_asm_scratch(title)

        local function refresh()
          set_buf_text(buf, 'Loading disassembly...\n')
          run_cmd(cmd, function(code, stdout, stderr)
            if code ~= 0 then
              set_buf_text(buf, ('ERROR (exit=%d)\n\n%s\n%s'):format(code, stdout, stderr))
              return
            end
            set_buf_text(buf, stdout)
          end)
        end

        -- Refresh shortcut
        vim.keymap.set('n', 'R', refresh, { buffer = buf, silent = true, desc = 'Refresh disassembly' })

        refresh()
      end

      vim.api.nvim_create_user_command('FwAsm', function()
        local objdump = pick_objdump()
        if not objdump then
          notify('arm-none-eabi-objdump not found in PATH', vim.log.levels.ERROR, 'FwAsm')
          return
        end

        local elf = elf_path_abs()
        if vim.fn.filereadable(elf) ~= 1 then
          notify('ELF not found: ' .. elf .. '\nRun :FwBuild first.', vim.log.levels.ERROR, 'FwAsm')
          return
        end

        fw_asm_open(objdump_cmd_full(elf), '[FW ASM] ' .. elf)
      end, {})

      vim.api.nvim_create_user_command('FwAsmFunc', function(opts)
        local objdump = pick_objdump()
        if not objdump then
          notify('arm-none-eabi-objdump not found in PATH', vim.log.levels.ERROR, 'FwAsmFunc')
          return
        end

        local elf = elf_path_abs()
        if vim.fn.filereadable(elf) ~= 1 then
          notify('ELF not found: ' .. elf .. '\nRun :FwBuild first.', vim.log.levels.ERROR, 'FwAsmFunc')
          return
        end

        local sym = (opts.args and opts.args ~= '') and opts.args or vim.fn.expand '<cword>'
        if not sym or sym == '' then
          notify('No symbol found. Put cursor on a function name or run :FwAsmFunc <symbol>', vim.log.levels.WARN, 'FwAsmFunc')
          return
        end

        fw_asm_open(objdump_cmd_func(elf, sym), ('[FW ASM FUNC] %s'):format(sym))
      end, { nargs = '?' })

      -- Adapter (cpptools)
      local open_debug_ad7 = vim.fn.stdpath 'data' .. '/mason/bin/OpenDebugAD7'
      dap.adapters.cppdbg = {
        id = 'cppdbg',
        type = 'executable',
        command = open_debug_ad7,
      }

      local gdb_path = pick_gdb() or 'gdb-multiarch'
      local server_addr = string.format('%s:%d', M.gdb_host, M.gdb_port)

      local common = {
        type = 'cppdbg',
        request = 'launch',
        cwd = '${workspaceFolder}',
        program = M.elf_path,

        MIMode = 'gdb',
        miDebuggerPath = gdb_path,
        miDebuggerServerAddress = server_addr,

        targetArchitecture = 'arm',

        runInTerminal = false,
        externalConsole = false,

        -- IMPORTANT: stop so cpptools can finish launching cleanly.
        -- You press <F5> to run (CubeIDE-style).
        stopAtEntry = true,

        setupCommands = {
          SC 'set confirm off',
          SC 'set pagination off',
          SC 'set endian little',
          SC 'set architecture arm',
        },
      }

      local flash_and_debug = vim.tbl_deep_extend('force', common, {
        name = 'STM32 (OpenOCD) - Flash + Debug',

        postRemoteConnectCommands = {
          SC 'monitor reset halt',
          SC 'load',
          SC 'monitor reset init',
          SC 'monitor halt',
          SC 'tbreak main',
          -- DO NOT "continue" here (cpptools treats ^running as an error)
        },
      })

      local attach_only = vim.tbl_deep_extend('force', common, {
        name = 'STM32 (OpenOCD) - Attach Only (No Flash)',
        postRemoteConnectCommands = {
          SC 'monitor reset halt',
        },
      })

      dap.configurations.c = { flash_and_debug, attach_only }
      dap.configurations.cpp = dap.configurations.c

      -- UI
      dapui.setup {}
      require('nvim-dap-virtual-text').setup {}

      dap.listeners.after.event_initialized['dapui_autoopen'] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated['dapui_autoclose'] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited['dapui_autoclose'] = function()
        dapui.close()
      end

      -- Keymaps
      local map = vim.keymap.set
      map('n', '<F5>', dap.continue, { desc = 'DAP: Continue' })
      map('n', '<F9>', dap.toggle_breakpoint, { desc = 'DAP: Toggle Breakpoint' })
      map('n', '<F10>', dap.step_over, { desc = 'DAP: Step Over' })
      map('n', '<F11>', dap.step_into, { desc = 'DAP: Step Into' })
      map('n', '<S-F11>', dap.step_out, { desc = 'DAP: Step Out' })

      map('n', '<leader>du', dapui.toggle, { desc = 'DAP UI: Toggle' })
      map('n', '<leader>dr', dap.repl.toggle, { desc = 'DAP: REPL Toggle' })
      map({ 'n', 'v' }, '<leader>de', function()
        dapui.eval()
      end, { desc = 'DAP UI: Eval' })

      -- Commands
      vim.api.nvim_create_user_command('FwBuild', function()
        make_target()
      end, {})

      vim.api.nvim_create_user_command('FwDebug', function()
        if not ensure_prereqs() then
          return
        end
        if not make_target() then
          return
        end
        dap.run(dap.configurations.c[1])
      end, {})

      vim.api.nvim_create_user_command('FwAttach', function()
        if not ensure_prereqs() then
          return
        end
        dap.run(dap.configurations.c[2])
      end, {})

      vim.api.nvim_create_user_command('FwDapInfo', function()
        notify(
          ('miDebuggerPath: %s\nOpenDebugAD7: %s\nELF: %s\nmiDebuggerServerAddress: %s\nstopAtEntry: true'):format(
            gdb_path,
            open_debug_ad7,
            M.elf_path,
            server_addr
          ),
          vim.log.levels.INFO,
          'FwDapInfo'
        )
      end, {})

      -- Quick Reference Guide (QRG): opens a scratch buffer with high-signal cheatsheet
      vim.api.nvim_create_user_command('QRG', function()
        vim.cmd('vnew')
        local buf = vim.api.nvim_get_current_buf()

        vim.bo[buf].buftype = 'nofile'
        vim.bo[buf].bufhidden = 'wipe'
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = true
        vim.bo[buf].filetype = 'markdown'

        local lines = {
          '# Quick Reference Guide (QRG)',
          '',
          '## Target (STM32 / OpenOCD)',
          '',
          '- Start OpenOCD:',
          '  ```bash',
          '  openocd -f interface/stlink.cfg -f target/stm32f4x.cfg',
          '  ```',
          '- In Neovim:',
          '  - `:FwBuild`  (`<leader>mb`) — build firmware',
          '  - `:FwDebug`  (`<leader>md`) — flash + debug (session starts halted)',
          '  - press `F5` to run / resume',
          '  - `:FwAttach` (`<leader>ma`) — attach only (no flash)',
          '',
          '### Target assembly views (static via objdump)',
          '- Full disassembly: `:FwAsm` (`<leader>sA`)',
          '- Function under cursor: `:FwAsmFunc` (`<leader>sa`)',
          '- In asm window: `q` close, `R` refresh',
          '',
          '### Debug keys (CubeIDE parity)',
          '- `F5` continue/resume',
          '- `F9` breakpoint toggle',
          '- `F10` step over',
          '- `F11` step into',
          '- `Shift+F11` step out',
          '- `<leader>du` toggle DAP UI',
          '- `<leader>dr` toggle REPL',
          '- `<leader>de` eval under cursor/selection',
          '',
          '## Host (native Linux)',
          '',
          '- Switch clangd to host:',
          '  ```bash',
          '  make -C host compdb && make switch-host',
          '  ```',
          '  Then in Neovim: `:LspRestart`',
          '',
          '- Build + run host:',
          '  ```bash',
          '  make -C host',
          '  ./build/host/host_app',
          '  ```',
          '',
          '- Host debug (terminal-first):',
          '  ```bash',
          '  gdb ./build/host/host_app',
          '  ```',
          '',
          '## Notes',
          '- If DAP behaves strangely, check port contention:',
          '  ```bash',
          '  ss -tnp | grep :3333',
          '  ```',
          '- DAP log: `:DapShowLog`',
          '',
          'Press `q` to close this window.',
        }

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false

        vim.keymap.set('n', 'q', '<cmd>bd!<CR>', { buffer = buf, silent = true, nowait = true, desc = 'Close QRG' })
      end, {})


      map('n', '<leader>mb', '<cmd>FwBuild<CR>', { desc = 'FW: Build' })
      map('n', '<leader>md', '<cmd>FwDebug<CR>', { desc = 'FW: Debug' })
      map('n', '<leader>ma', '<cmd>FwAttach<CR>', { desc = 'FW: Attach' })
      map('n', '<leader>sA', '<cmd>FwAsm<CR>', { desc = 'FW: Assembly (full ELF)' })
      map('n', '<leader>sa', '<cmd>FwAsmFunc<CR>', { desc = 'FW: Assembly (function under cursor)' })
    end,
  },
}
