# Neovim DAP Guide (Cube32 IDE Equivalent on Windows)

## Overview

Neovim’s DAP (Debug Adapter Protocol) integration allows you to debug code inside Neovim with functionality comparable to a full IDE (like STM32CubeIDE on Windows). Using the [nvim-dap plugin][21], you can launch or attach to applications, set breakpoints, step through code, and inspect program state – all from within Neovim.

This guide provides a comprehensive walkthrough on using Neovim’s DAP setup, mirroring typical IDE debugging workflows. We assume you have already installed and configured nvim-dap (and any language-specific adapters or servers such as GDB/OpenOCD for STM32 on Windows) and optionally a UI extension like nvim-dap-ui for an IDE-like interface.

By the end of this guide, you should be able to perform all common debugging tasks in Neovim – setting breakpoints, running and controlling program execution, inspecting variables, and more – just as you would in a graphical IDE.

---

## Starting Workflow

Let’s begin with a quick starting workflow to demonstrate the basic debugging cycle in Neovim DAP. This will cover launching a debug session, hitting a breakpoint, and examining program state:

1. **Open Your Project in Neovim:**

   * Launch Neovim and open the project or source file you want to debug.
   * Ensure you’re in the project’s root directory so that DAP configurations (if any) can be found.
   * For embedded targets or special setups, make sure any required debug server (e.g. OpenOCD or ST-Link server for STM32 on Windows) is running or configured to auto-start via DAP.

2. **Set an Initial Breakpoint:**

   * Navigate to a line of code where you want execution to pause.
   * Press `F9` or use the command `:DapToggleBreakpoint` to set a breakpoint.
   * Neovim will highlight the line or mark it (often with a red `●` sign) to indicate an active breakpoint.

3. **Launch the Debug Session:**

   * Press `F5` (bound to `:DapContinue`) to start debugging.
   * If you have multiple debug configurations, a selection menu may appear.

4. **Hit the Breakpoint:**

   * The program will run until it hits the breakpoint you set.
   * Execution pauses and the current line is highlighted (often with a yellow arrow).

5. **Inspect State (Briefly):**

   * If `nvim-dap-ui` is enabled, side windows may open showing Scopes, Variables, Breakpoints, Stack, etc.
   * Toggle the UI with `<Leader>du` if not auto-opened.

Now that you’ve started a debug session and paused execution, you're ready to explore deeper workflows.

---

## Command Reference

| Keybinding / Command          | Description                                       |
| ----------------------------- | ------------------------------------------------- |
| `F5` / `:DapContinue`         | Launch or continue execution of the program       |
| `Shift+F5` / `:DapTerminate`  | Stop debugging session                            |
| `F9` / `:DapToggleBreakpoint` | Toggle breakpoint on current line                 |
| `F10` / `:DapStepOver`        | Step over the current line                        |
| `F11` / `:DapStepInto`        | Step into the function                            |
| `Shift+F11` / `:DapStepOut`   | Step out of current function                      |
| `F4` / `:DapRunToCursor`      | Continue execution to the current cursor position |
| `F6` / `:DapPause`            | Pause execution                                   |
| `:DapRestart` / `:DapRunLast` | Restart or rerun last configuration               |
| `<Leader>dr` / `:DapReplOpen` | Open DAP REPL console                             |
| `<Leader>du` / `:DapUIToggle` | Toggle DAP UI panel                               |
| `K` or `<Leader>dh`           | Hover to inspect variable under cursor            |
| `<Leader>de`                  | Evaluate expression in visual or normal mode      |

*You can customize these in your own Neovim config. These examples use common conventions.*

---

## Workflows

Each workflow below mirrors a real-world IDE behavior. Follow these to master embedded debugging in Neovim:

### 1. Launching a New Debug Session

### 2. Attaching to a Running Process or Target

### 3. Setting a Breakpoint

### 4. Setting a Conditional Breakpoint

### 5. Setting a Logpoint (Breakpoint with Log Message)

### 6. Continuing Execution (Resume Program)

### 7. Pausing the Program (Break All)

### 8. Stepping Over a Line of Code

### 9. Stepping Into a Function

### 10. Stepping Out of a Function

### 11. Inspecting Variables and Expressions (Scopes)

### 12. Watching Variables and Expressions

### 13. Viewing the Call Stack (Backtrace) and Switching Frames

### 14. Evaluating Expressions in the REPL Console

### 15. Using the Debug UI Panels (DAP UI)

### 16. Stopping the Debug Session

### 17. Restarting a Debug Session Quickly

### 18. Additional Tips and Advanced Workflows

Each of these workflows is detailed with key steps, Neovim commands, and IDE analogies in the full guide.

---

## Conclusion

With this guide, you now have an extensive understanding of how to debug in Neovim using `nvim-dap` and related plugins. You can replicate virtually every debugging action you would perform in STM32CubeIDE – breakpoints, stepping, inspecting memory/registers, logging, watch expressions, and more.

Explore each workflow as you debug real projects. Tweak your keybindings and UI layout to match your preferences. And if you’re doing embedded work (e.g., STM32 + OpenOCD), rest assured this setup is powerful enough for professional-level debugging inside Neovim.

---

*Sources: Based on real usage and configuration of `nvim-dap`, `nvim-dap-ui`, STM32 debugging, and GDB/OpenOCD integration.*

