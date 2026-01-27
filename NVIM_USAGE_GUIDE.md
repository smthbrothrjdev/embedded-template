# Neovim DAP for STM32  — CubeIDE-Equivalent Debugging Guide

This guide documents **a working Neovim + nvim-dap + cpptools (OpenDebugAD7) + OpenOCD + GDB** setup for **STM32F4 (Cortex-M4)**, using:

- **Firmware ELF**: `${workspaceFolder}/build/target/firmware.elf`
- **GDB server**: `127.0.0.1:3333` (OpenOCD)
- **Adapter**: `cppdbg` via **OpenDebugAD7** (Mason `cpptools`)
- **Debugger**: `arm-none-eabi-gdb` (preferred) or `gdb-multiarch` (fallback)

> **Key rule we learned the hard way (cpptools/OpenDebugAD7):**
> **Do NOT run `continue` inside `setupCommands` / `postRemoteConnectCommands`.**  
> cpptools expects MI commands to return `^done`; `continue` returns `^running` and cpptools treats it as an error.  
> **Instead:** let the session start (halted), then press **`F5`** to run.

---

## Table of Contents

- [1. Overview](#1-overview)
- [2. Our Implementation](#2-our-implementation)
  - [2.1 What Runs Where](#21-what-runs-where)
  - [2.2 The Two Debug Configs](#22-the-two-debug-configs)
  - [2.3 Why `stopAtEntry=true` matters](#23-why-stopatentrytrue-matters)
  - [2.4 Prereq checks we added](#24-prereq-checks-we-added)
- [3. Starting Workflow (fast path)](#3-starting-workflow-fast-path)
- [4. Command Reference (IDE parity)](#4-command-reference-ide-parity)
  - [4.1 Our Keybinds](#41-our-keybinds)
  - [4.2 Our User Commands](#42-our-user-commands)
  - [4.3 Common DAP Commands (no key by default)](#43-common-dap-commands-no-key-by-default)
  - [4.4 “CubeIDE buttons” mapped to Neovim](#44-cubeide-buttons-mapped-to-neovim)
- [5. Workflows (26 total)](#5-workflows-26-total)
  - [01. OpenOCD Start/Stop](#01-openocd-startstop)
  - [02. Sanity Check GDB ↔ OpenOCD](#02-sanity-check-gdb--openocd)
  - [03. Flash + Debug (our primary)](#03-flash--debug-our-primary)
  - [04. Attach Only (no flash)](#04-attach-only-no-flash)
  - [05. “Run” after launch (CubeIDE Resume)](#05-run-after-launch-cubeide-resume)
  - [06. Toggle Breakpoints](#06-toggle-breakpoints)
  - [07. Conditional Breakpoints](#07-conditional-breakpoints)
  - [08. Logpoints (print without stopping)](#08-logpoints-print-without-stopping)
  - [09. Step Over](#09-step-over)
  - [10. Step Into](#10-step-into)
  - [11. Step Out](#11-step-out)
  - [12. Run to Cursor](#12-run-to-cursor)
  - [13. Pause / Break All](#13-pause--break-all)
  - [14. View Locals (Scopes)](#14-view-locals-scopes)
  - [15. Evaluate Expression / Hover Inspect](#15-evaluate-expression--hover-inspect)
  - [16. Watches (tracked expressions)](#16-watches-tracked-expressions)
  - [17. Call Stack + Switching Frames](#17-call-stack--switching-frames)
  - [18. Threads (when applicable)](#18-threads-when-applicable)
  - [19. REPL: GDB “monitor” + commands](#19-repl-gdb-monitor--commands)
  - [20. Registers + Disassembly](#20-registers--disassembly)
  - [21. Memory Inspection (RAM/Flash/peripherals)](#21-memory-inspection-ramflashperipherals)
  - [22. Reset/Halt/Restart patterns](#22-resethaltrestart-patterns)
  - [23. Reflash after code change (tight loop)](#23-reflash-after-code-change-tight-loop)
  - [24. Handling “adapter didn’t respond” / blank windows](#24-handling-adapter-didnt-respond--blank-windows)
  - [25. Port 3333 already connected (the big gotcha)](#25-port-3333-already-connected-the-big-gotcha)
  - [26. Logging + DapShowLog](#26-logging--dapshowlog)
- [6. Troubleshooting Cheatsheet](#6-troubleshooting-cheatsheet)
- [7. Appendix: Our `dap-embedded.lua`](#7-appendix-our-dap-embeddedlua)

---

## 1. Overview

Neovim can match STM32CubeIDE debugging capability by combining:

- **nvim-dap**: DAP client inside Neovim
- **cpptools (OpenDebugAD7)**: Debug adapter (Microsoft MI engine)
- **GDB**: `arm-none-eabi-gdb` or `gdb-multiarch`
- **OpenOCD**: GDB server talking to ST-Link and the MCU
- **nvim-dap-ui + virtual-text**: IDE-like panes (variables, stack, breakpoints, watches, REPL) and inline values

This guide is **specific to my implementation** (paths, commands, ports, keymaps, and the cpptools quirks we hit).

---

## 2. Implementation

### 2.1 What Runs Where

**You run OpenOCD externally** (separate terminal process):

```bash
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
```

OpenOCD exposes:

- **GDB server**: `127.0.0.1:3333`
- **Telnet**: `127.0.0.1:4444`
- **TCL**: `127.0.0.1:6666`

**Neovim** then runs:

- `OpenDebugAD7` (Mason `cpptools`) as the DAP adapter
- `gdb-multiarch` or `arm-none-eabi-gdb` as the MI debugger client
- Connects to OpenOCD at `127.0.0.1:3333`

### 2.2 The Two Debug Configs

We define two configurations for C/C++:

1. **Flash + Debug**  
   - Connect to OpenOCD
   - `monitor reset halt`
   - `load` (flash)
   - break at `main` (`tbreak main`)
   - **STOP** (no auto-continue)
   - You press **F5** to run

2. **Attach Only (No Flash)**  
   - Connect to OpenOCD
   - `monitor reset halt`
   - STOP (useful when firmware already flashed)

### 2.3 Why `stopAtEntry=true` matters

cpptools/OpenDebugAD7 wants the launch sequence to “settle” and return `^done` for setup commands.

We set:

- `stopAtEntry = true`

So the session comes up **halted**, DAP UI initializes cleanly, then you explicitly run with **F5**.

### 2.4 Prereq checks we added

Before launching we verify:

- GDB exists (`arm-none-eabi-gdb` or `gdb-multiarch` or `gdb`)
- OpenDebugAD7 exists (`~/.local/share/nvim/mason/bin/OpenDebugAD7`)
- OpenOCD is listening on port **3333**
- **No other established client** is connected to `:3333` (this was our main failure mode)

---

## 3. Starting Workflow (fast path)

**This is the daily “CubeIDE Debug” loop.**

1. **Start OpenOCD** in a terminal:
   ```bash
   openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
   ```

2. **Verify port is listening**:
   ```bash
   ss -ltnp | grep 3333
   ```

3. Open project in Neovim (workspace root).

4. Build:
   - `:FwBuild` or **`<leader>mb`**

5. Debug (flash + debug):
   - `:FwDebug` or **`<leader>md`**

6. UI opens, target is halted.  
   Now press:
   - **`F5`** to run (Resume)

7. Use breakpoints/step/inspect like you would in CubeIDE.

---

## 4. Command Reference (IDE parity)

### 4.1 Our Keybinds

| Key | Action | Neovim Function |
|---|---|---|
| `F5` | Continue / Resume | `dap.continue()` |
| `F9` | Toggle breakpoint | `dap.toggle_breakpoint()` |
| `F10` | Step over | `dap.step_over()` |
| `F11` | Step into | `dap.step_into()` |
| `Shift+F11` | Step out | `dap.step_out()` |
| `<leader>du` | Toggle DAP UI | `dapui.toggle()` |
| `<leader>dr` | Toggle REPL | `dap.repl.toggle()` |
| `<leader>de` | Eval under cursor / selection | `dapui.eval()` |
| `<leader>mb` | Firmware build | `:FwBuild` |
| `<leader>md` | Firmware flash + debug | `:FwDebug` |
| `<leader>ma` | Firmware attach-only | `:FwAttach` |

> **Important:** We intentionally do **not** “auto-run” from setup/postRemoteConnect.  
> Press **F5** after session starts.

### 4.2 Our User Commands

| Command | What it does |
|---|---|
| `:FwBuild` | `make -C target` (saves buffers first) |
| `:FwDebug` | prereq checks → build → start **Flash + Debug** config |
| `:FwAttach` | prereq checks → start **Attach Only** config |
| `:FwDapInfo` | prints current adapter paths / ELF / server addr |

### 4.3 Common DAP Commands (no key by default)

These exist in `nvim-dap` but may not be mapped:

- `:DapTerminate` — stop session  
- `:DapDisconnect` — detach (adapter-dependent)
- `:DapRestart` / `:DapRunLast` — rerun last session
- `:DapShowLog` — show DAP log buffer
- `:lua require('dap').set_breakpoint(<cond>)` — conditional bp
- `:lua require('dap').run_to_cursor()` — run to cursor (if configured)
- `:lua require('dap').clear_breakpoints()` — clear all breakpoints

### 4.4 “CubeIDE buttons” mapped to Neovim

| CubeIDE button | Neovim equivalent |
|---|---|
| Debug (bug icon) | `:FwDebug` / `<leader>md` |
| Resume | `F5` |
| Pause | `:DapPause` (map if desired) |
| Stop | `:DapTerminate` (map if desired) |
| Step Over | `F10` |
| Step Into | `F11` |
| Step Return | `Shift+F11` |
| Toggle Breakpoint | `F9` |
| Expressions/Watch | DAP UI Watches + `<leader>de` |
| Variables | DAP UI Scopes |
| Call Stack | DAP UI Stacks |
| Debug Console | DAP REPL (`<leader>dr`) |

---

## 5. Workflows (26 total)

### 01. OpenOCD Start/Stop

**Start:**
```bash
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
```

**Stop:**
- `Ctrl+C` in the OpenOCD terminal

**Verify listening:**
```bash
ss -ltnp | grep 3333
```

---

### 02. Sanity Check GDB ↔ OpenOCD

This verifies the **core pipeline** independent of Neovim.

```bash
gdb-multiarch build/target/firmware.elf -q \
  -ex "set confirm off" \
  -ex "target remote 127.0.0.1:3333" \
  -ex "monitor reset halt" \
  -ex "quit"
```

Expected: connects, halts, and does not “broken pipe”.

---

### 03. Flash + Debug (our primary)

1. Start OpenOCD (Workflow 01)
2. In Neovim:
   - `<leader>md` (or `:FwDebug`)
3. When session starts (halted), press:
   - **`F5`** (Resume)

This mimics “Debug” then “Resume” in CubeIDE.

---

### 04. Attach Only (no flash)

Use when firmware is already flashed and you want to connect without `load`.

1. Start OpenOCD
2. Neovim:
   - `<leader>ma` (or `:FwAttach`)
3. Press **F5** if you want to run.

---

### 05. “Run” after launch (CubeIDE Resume)

Because we avoid `continue` in setup commands:

- Start session (`:FwDebug`)
- Then press **`F5`** to run

If you forget this, you’ll think “nothing happens”.

---

### 06. Toggle Breakpoints

- Move cursor to line
- Press **`F9`**
- Press **`F9`** again to remove

Use with `F5` to run until breakpoint.

---

### 07. Conditional Breakpoints

Set a breakpoint that only triggers when condition is true:

```vim
:lua require('dap').set_breakpoint(vim.fn.input('Condition: '))
```

Example conditions (GDB-style):
- `i == 10`
- `ptr == 0`
- `count > 100`

Then `F5`.

---

### 08. Logpoints (print without stopping)

```vim
:lua require('dap').set_breakpoint(nil, nil, vim.fn.input('Log message: '))
```

Example:
- `hit loop, i={i}`

Output appears in REPL/console, program does not stop.

---

### 09. Step Over

- While paused: **`F10`**
- Use for line-by-line progress without diving into calls.

---

### 10. Step Into

- While paused on a call line: **`F11`**
- Use to debug inside the called function.

---

### 11. Step Out

- While inside a function: **`Shift+F11`**
- Runs until return to caller.

---

### 12. Run to Cursor

If you have a mapping for `run_to_cursor`, use it.
If not, emulate:

1. Put cursor on target line
2. Press `F9` (temp breakpoint)
3. Press `F5` (run)
4. Remove breakpoint (`F9`) once hit

---

### 13. Pause / Break All

If you map `dap.pause()` (recommended), you can halt a running target.

Manual approach without mapping:
- Use GDB in REPL: `interrupt` (adapter dependent)
- Or OpenOCD telnet and halt (advanced)

---

### 14. View Locals (Scopes)

When paused:
- Toggle UI: **`<leader>du`**
- Look in **Scopes** panel:
  - locals
  - arguments
  - statics/globals (depending on adapter)

Expand structs/arrays with Enter.

---

### 15. Evaluate Expression / Hover Inspect

- Place cursor on symbol
- Use **`<leader>de`** to evaluate
- Or evaluate selection (visual mode) with `<leader>de`

Examples:
- `myVar`
- `myStruct.field`
- `*(uint32_t*)0x20000000`

---

### 16. Watches (tracked expressions)

In dap-ui Watches panel:
- add expressions you want constantly visible
- they update each pause/step

Use cases:
- loop counter
- flags/state variables
- a peripheral register expression

---

### 17. Call Stack + Switching Frames

In **Stacks** panel:
- select a frame to view caller context
- variables panel updates to that frame’s locals

CubeIDE parity: “Call Stack” view.

---

### 18. Threads (when applicable)

If your debug target exposes threads/RTOS tasks:
- inspect threads panel (if configured)
- switch between them to see stacks

Even without explicit RTOS support, some setups show a single thread.

---

### 19. REPL: GDB “monitor” + commands

Open REPL:
- **`<leader>dr`**

Then run common GDB operations:

- break at main (if you didn’t already):
  - `tbreak main`
- continue:
  - `continue`
- show registers:
  - `info registers`
- examine memory:
  - `x/16wx 0x20000000`
- OpenOCD monitor commands:
  - `monitor reset halt`
  - `monitor halt`
  - `monitor reset init`

> Using REPL is how you replicate “Debug Console” + “Monitor” in IDEs.

---

### 20. Registers + Disassembly

Registers:
- REPL: `info registers`

Disassembly:
- REPL: `disassemble /m main`
- Or:
  - `x/10i $pc`

Use when:
- you stepped into startup code
- you’re chasing a hard fault / invalid jump
- you want to see actual instructions

---

### 21. Memory Inspection (RAM/Flash/peripherals)

Typical patterns (REPL, GDB):

- RAM dump words:
  - `x/32wx 0x20000000`
- Flash dump words:
  - `x/32wx 0x08000000`
- Peripheral register read (example address):
  - `x/wx 0x40021000`

Or cast + dereference:
- `p *(uint32_t*)0x40021000`

This mirrors CubeIDE “Memory” view.

---

### 22. Reset/Halt/Restart patterns

**Halt now:**
- REPL: `monitor halt`

**Reset + halt (common before flashing):**
- REPL: `monitor reset halt`

**Reset + run:**
- REPL:
  - `monitor reset run`
  - or `monitor reset init` then `continue`

Our config already does reset/halt and sets `tbreak main` during connect.

---

### 23. Reflash after code change (tight loop)

1. Stop session:
   - `:DapTerminate` (map it if you want IDE-like Shift+F5)
2. Edit code
3. Build:
   - `<leader>mb` / `:FwBuild`
4. Flash + Debug:
   - `<leader>md` / `:FwDebug`
5. Run:
   - `F5`

This is the “edit → rebuild → debug” loop.

---

### 24. Handling “adapter didn’t respond” / blank windows

If DAP UI opens but looks empty or session ends instantly:

1. Check DAP log:
   - `:DapShowLog`
2. Check OpenOCD terminal output
3. Verify port/listening:
   - `ss -ltnp | grep 3333`
4. Verify no established clients:
   - `ss -tnp | grep :3333`
5. Re-run the sanity check (Workflow 02)

---

### 25. Port 3333 already connected 

This is a common root cause for “monitor not supported”, “broken pipe”, random disconnects.

Check:
```bash
ss -tnp | grep :3333
```

If you see an **ESTABLISHED** connection (some other client), kill/close it, then relaunch.

Our `FwDebug` checks this and refuses to run if the port is already in use.

---

### 26. Logging + DapShowLog

When anything is weird:

- `:DapShowLog`  
- also check OpenOCD log output

Most “mystery failures” become obvious there:
- wrong architecture
- `continue` in postRemoteConnect
- remote disconnected
- port already in use

---

## 6. Troubleshooting Cheatsheet

**Symptom:** `monitor command not supported by this target`  
- Usually means you’re not actually connected correctly (or connection broke).  
- Run sanity check (Workflow 02) and check port occupancy (Workflow 25).

**Symptom:** `Broken pipe` / `Connection reset by peer`  
- Another client connected, OpenOCD restarted, or GDB got booted.  
- Check `ss -tnp | grep :3333`.

**Symptom:** DAP error about `continue` returning `running`  
- Remove `continue` from setup/postRemoteConnect.  
- Press **F5** manually once session starts.

**Symptom:** Windows open but show nothing  
- Session likely terminated immediately. Check `:DapShowLog`.

---

## 7. Appendix: Our `dap-embedded.lua`

> Included here so the guide remains “specific to our implementation”.

```lua
-- Key rule for cpptools (OpenDebugAD7):
-- Do NOT run "continue" inside setup/postRemoteConnect commands.
-- cpptools expects those commands to return MI ^done, but continue returns ^running.

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "theHamsta/nvim-dap-virtual-text",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      local M = {}
      M.elf_path = "${workspaceFolder}/build/target/firmware.elf"
      M.gdb_host = "127.0.0.1"
      M.gdb_port = 3333

      local function notify(msg, level, title)
        vim.notify(msg, level or vim.log.levels.INFO, { title = title or "DAP" })
      end

      local function executable_or_nil(bin)
        return (vim.fn.executable(bin) == 1) and bin or nil
      end

      local function pick_gdb()
        return executable_or_nil("arm-none-eabi-gdb")
          or executable_or_nil("gdb-multiarch")
          or executable_or_nil("gdb")
      end

      local function SC(cmd)
        return { text = cmd }
      end

      local function make_target()
        vim.cmd("wall")
        local out = vim.fn.system({ "make", "-C", "target" })
        if vim.v.shell_error ~= 0 then
          notify(out, vim.log.levels.ERROR, "FwBuild failed")
          return false
        end
        notify("Build OK", vim.log.levels.INFO, "FwBuild")
        return true
      end

      local function is_openocd_listening()
        local cmd = string.format([[ss -ltnH "sport = :%d" 2>/dev/null | awk '{print $4}']], M.gdb_port)
        local out = vim.fn.system(cmd)
        if vim.v.shell_error ~= 0 then
          return true
        end
        return out:match("127%.0%.0%.1:" .. M.gdb_port) ~= nil
      end

      local function any_established_gdb_clients()
        local cmd = string.format([[ss -tnHp state established "( sport = :%d )" 2>/dev/null]], M.gdb_port)
        local out = vim.fn.system(cmd)
        if vim.v.shell_error ~= 0 then
          return false, ""
        end
        local has = out ~= nil and out:match("%S") ~= nil
        return has, out
      end

      local function ensure_prereqs()
        local gdb = pick_gdb()
        if not gdb then
          notify("No GDB found (arm-none-eabi-gdb / gdb-multiarch / gdb)", vim.log.levels.ERROR, "DAP prereq")
          return false
        end

        local open_debug_ad7 = vim.fn.stdpath("data") .. "/mason/bin/OpenDebugAD7"
        if vim.fn.executable(open_debug_ad7) ~= 1 then
          notify("OpenDebugAD7 missing. Install via :Mason (package: cpptools).", vim.log.levels.ERROR, "DAP prereq")
          return false
        end

        if not is_openocd_listening() then
          notify(
            string.format("OpenOCD not listening on %s:%d. Start OpenOCD first.", M.gdb_host, M.gdb_port),
            vim.log.levels.ERROR,
            "DAP prereq"
          )
          return false
        end

        local has_estab, estab_out = any_established_gdb_clients()
        if has_estab then
          notify(
            "Port 3333 already has an established client connection.\n" ..
              "Close the other client and try again.\n\n" .. estab_out,
            vim.log.levels.ERROR,
            "DAP prereq"
          )
          return false
        end

        return true
      end

      -- Adapter (cpptools)
      local open_debug_ad7 = vim.fn.stdpath("data") .. "/mason/bin/OpenDebugAD7"
      dap.adapters.cppdbg = {
        id = "cppdbg",
        type = "executable",
        command = open_debug_ad7,
      }

      local gdb_path = pick_gdb() or "gdb-multiarch"
      local server_addr = string.format("%s:%d", M.gdb_host, M.gdb_port)

      local common = {
        type = "cppdbg",
        request = "launch",
        cwd = "${workspaceFolder}",
        program = M.elf_path,

        MIMode = "gdb",
        miDebuggerPath = gdb_path,
        miDebuggerServerAddress = server_addr,

        targetArchitecture = "arm",

        runInTerminal = false,
        externalConsole = false,

        -- IMPORTANT: stop so cpptools can finish launching cleanly.
        -- You press <F5> to run (CubeIDE-style).
        stopAtEntry = true,

        setupCommands = {
          SC("set confirm off"),
          SC("set pagination off"),
          SC("set endian little"),
          SC("set architecture arm"),
        },
      }

      local flash_and_debug = vim.tbl_deep_extend("force", common, {
        name = "STM32 (OpenOCD) - Flash + Debug",

        postRemoteConnectCommands = {
          SC("monitor reset halt"),
          SC("load"),
          SC("monitor reset init"),
          SC("monitor halt"),
          SC("tbreak main"),
          -- DO NOT "continue" here (cpptools treats ^running as an error)
        },
      })

      local attach_only = vim.tbl_deep_extend("force", common, {
        name = "STM32 (OpenOCD) - Attach Only (No Flash)",
        postRemoteConnectCommands = {
          SC("monitor reset halt"),
        },
      })

      dap.configurations.c = { flash_and_debug, attach_only }
      dap.configurations.cpp = dap.configurations.c

      -- UI
      dapui.setup({})
      require("nvim-dap-virtual-text").setup({})

      dap.listeners.after.event_initialized["dapui_autoopen"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_autoclose"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_autoclose"] = function()
        dapui.close()
      end

      -- Keymaps
      local map = vim.keymap.set
      map("n", "<F5>", dap.continue, { desc = "DAP: Continue" })
      map("n", "<F9>", dap.toggle_breakpoint, { desc = "DAP: Toggle Breakpoint" })
      map("n", "<F10>", dap.step_over, { desc = "DAP: Step Over" })
      map("n", "<F11>", dap.step_into, { desc = "DAP: Step Into" })
      map("n", "<S-F11>", dap.step_out, { desc = "DAP: Step Out" })

      map("n", "<leader>du", dapui.toggle, { desc = "DAP UI: Toggle" })
      map("n", "<leader>dr", dap.repl.toggle, { desc = "DAP: REPL Toggle" })
      map({ "n", "v" }, "<leader>de", function()
        dapui.eval()
      end, { desc = "DAP UI: Eval" })

      -- Commands
      vim.api.nvim_create_user_command("FwBuild", function()
        make_target()
      end, {})

      vim.api.nvim_create_user_command("FwDebug", function()
        if not ensure_prereqs() then
          return
        end
        if not make_target() then
          return
        end
        dap.run(dap.configurations.c[1])
      end, {})

      vim.api.nvim_create_user_command("FwAttach", function()
        if not ensure_prereqs() then
          return
        end
        dap.run(dap.configurations.c[2])
      end, {})

      vim.api.nvim_create_user_command("FwDapInfo", function()
        notify(
          ("miDebuggerPath: %s\nOpenDebugAD7: %s\nELF: %s\nmiDebuggerServerAddress: %s\nstopAtEntry: true"):format(
            gdb_path,
            open_debug_ad7,
            M.elf_path,
            server_addr
          ),
          vim.log.levels.INFO,
          "FwDapInfo"
        )
      end, {})

      map("n", "<leader>mb", "<cmd>FwBuild<CR>", { desc = "FW: Build" })
      map("n", "<leader>md", "<cmd>FwDebug<CR>", { desc = "FW: Debug" })
      map("n", "<leader>ma", "<cmd>FwAttach<CR>", { desc = "FW: Attach" })
    end,
  },
}
```
