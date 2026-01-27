# Embedded Host / Target Workflow (Kickstart.nvim)

This repository documents a **minimal, transparent, IDE-independent workflow** for doing **embedded C development** with **Kickstart.nvim**, supporting:

* **Host builds** (native Linux Mint / Ubuntu)
* **Target builds** (bare-metal STM32, example: STM32F411RE)
* **clangd-based editor intelligence** via `compile_commands.json`
* **GDB + OpenOCD debugging** equivalent to CubeIDE (breakpoints, stepping, registers, memory)

This README captures the *exact steps we validated end‑to‑end* and can be followed on a **fresh Linux install**.

---

## Mental Model (Read This First)

Think in layers:

* **Build system** (Make + GCC / ARM GCC) → produces binaries
* **Bear** → records real compiler invocations
* **compile_commands.json** → source of truth for clangd
* **clangd (via Neovim)** → editor intelligence only
* **OpenOCD + GDB** → flashing + debugging on real hardware

> Neovim does **not** build or debug firmware.
> It becomes powerful only when connected to the real tools.

---

## 1️⃣ Fresh System Setup (Linux Mint / Ubuntu)

### Required packages

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  make \
  clangd \
  bear \
  gcc-arm-none-eabi \
  gdb-multiarch \
  openocd \
  netcat-openbsd
```

### Why each matters

| Package           | Why                            |
| ----------------- | ------------------------------ |
| build-essential   | native compiler + make         |
| clangd            | LSP for C/C++                  |
| bear              | generate compile_commands.json |
| gcc-arm-none-eabi | STM32 cross-compiler           |
| gdb-multiarch     | reliable Cortex‑M debugger     |
| openocd           | on‑chip debug server           |
| netcat-openbsd    | GDB TCP workaround             |

### Verify installation

```bash
clangd --version
bear --version
arm-none-eabi-gcc --version
gdb-multiarch --version
openocd --version
```

---

## 2️⃣ Repository Layout (Validated)

```text
myProj/
├─ host/                 # Native Linux code
│  ├─ src/
│  └─ include/
├─ target/               # Embedded STM32 code
│  ├─ src/
│  ├─ include/
│  └─ stm32/
│     ├─ startup/        # startup_stm32f411xe.s
│     ├─ linker/         # STM32F411XX_FLASH.ld
│     ├─ system/         # system_stm32f4xx.c + Inc/
│     └─ cmsis/          # Drivers/CMSIS/...
├─ build/
│  ├─ host/
│  └─ target/
├─ Makefile              # top‑level switcher
└─ compile_commands.json # symlink (host OR target)
```

Only **one** `compile_commands.json` is active at a time.

---

## 3️⃣ clangd + Bear Workflow (Editor Intelligence)

### Generate compile database

```bash
make -C target compdb
make switch-target
```

Then restart LSP in Neovim:

```vim
:LspRestart
```

### Important Bear rule

> Bear only records **real compiler invocations**.
> If nothing recompiles, the database will be empty (`[]`).

That’s why `compdb` forces a clean rebuild.

---

## Host-Side Development (Native Linux)

This document describes the **host-side workflow** for this project: building and running code **natively on Linux** (Mint / Ubuntu) alongside the embedded target workflow.

The host side exists to enable **fast iteration**, **testing**, and **tooling** without requiring hardware flashing or debugging.

---

### Purpose of the Host Side

Typical use cases for host code:

- validating algorithms and data structures
- writing parsers, encoders, and state machines
- building simulators or test harnesses
- experimenting with logic before porting to embedded
- reproducing bugs without hardware in the loop

The host build is **native Linux** and intentionally avoids embedded dependencies.

---

### Host Toolchain

The host side uses the standard system toolchain:

- `gcc` (or `clang`)
- `make`
- `bear` (for `compile_commands.json`)
- `clangd` (editor intelligence)

No cross-compilation is involved.

---

### Directory Layout

```
host/
├─ src/        # host-only source files
├─ include/    # host-only headers
└─ Makefile
```

Host code **must not depend on**:

- CMSIS
- STM32 headers
- linker scripts
- OpenOCD
- embedded startup code

If code is intended to be shared, it should live in a neutral location (e.g. `common/`) and be protected with `#ifdef`s.

---

### Building the Host Program

From the repository root:

```bash
make -C host
```

Typical output:

```
build/host/
└─ host_app
```

Run it directly:

```bash
./build/host/host_app
```

This allows fast testing without touching embedded hardware.

---

### Host Compile Database (clangd Support)

To enable full editor intelligence for host code:

```bash
make -C host compdb
make switch-host
```

Then restart clangd in Neovim:

```vim
:LspRestart
```

After this:

- system headers resolve correctly
- warnings/errors appear inline
- jump-to-definition works
- completion matches the real compiler

---

### Switching Between Host and Target (Critical)

Only **one** `compile_commands.json` can be active at a time.

| Mode   | Commands |
|------|----------|
| Host   | `make -C host compdb && make switch-host` |
| Target | `make -C target compdb && make switch-target` |

After switching modes, always run:

```vim
:LspRestart
```

This keeps clangd synchronized with the active build context.

---

### Debugging Host Code (Optional)

Host binaries can be debugged using standard tools:

```bash
gdb ./build/host/host_app
```

This can later be integrated into Neovim using `nvim-dap` with a native adapter.

Host debugging is **independent** from the embedded OpenOCD + GDB workflow.

---

### Host vs Target: Mental Separation

A useful rule of thumb:

| Question | Host | Target |
|--------|------|--------|
| Runs on Linux | ✅ | ❌ |
| Uses STM32 headers | ❌ | ✅ |
| Uses linker script | ❌ | ✅ |
| Requires flashing | ❌ | ✅ |
| Fast iteration | ✅ | ❌ |

Maintaining this boundary prevents subtle bugs and tooling confusion.

---

### Philosophy

The host side exists for **speed and safety**.  
The target side exists for **truth and hardware reality**.

Effective embedded workflows use **both deliberately**, not interchangeably.

---

## 4️⃣ Bare‑Metal Target Build (No HAL)

This project intentionally **does NOT use HAL yet**.

We compile only:

* `startup_stm32f411xe.s`
* `system_stm32f4xx.c`
* `main.c`

HAL files were explicitly removed to avoid dependency explosions.

### Output artifacts

```text
build/target/
├─ firmware.elf   # debug + symbols
├─ firmware.bin   # raw binary
├─ firmware.hex   # intel hex
├─ firmware.map   # linker truth
```

---

## 5️⃣ Debugging with OpenOCD + GDB (CubeIDE Equivalent)

### Start OpenOCD (Terminal A)

```bash
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
```

Confirm:

```
Listening on port 3333 for gdb connections
```

### Start GDB (Terminal B)

```bash
cd myProj
gdb-multiarch build/target/firmware.elf
```

### Connect (GDB TCP workaround)

Some GDB builds fail on `host:port` parsing. This always works:

```gdb
target remote | nc 127.0.0.1 3333
```

Then:

```gdb
monitor reset halt
load
break main
continue
```

If it stops at `main`, debugging is fully functional.

---

## 6️⃣ GDB Guide (IDE Parity + Real Embedded Workflows)

This section is meant to replace the “IDE panels” you’re used to (CubeIDE):

* **Breakpoints** → `break`, `watch`
* **Step/continue** → `next`, `step`, `continue`, `finish`
* **Registers view** → `info registers`
* **Memory view** → `x/... <addr>`
* **Call stack** → `backtrace`
* **Variables / locals** → `print`, `info locals`, `info args`

> Important: In this workflow, OpenOCD is the debug server and GDB is the client.

### 6.0 Connect + load (known-good sequence)

Terminal A (OpenOCD):

```bash
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
```

Terminal B (GDB):

```bash
gdb-multiarch build/target/firmware.elf
```

Inside GDB (TCP workaround that always works):

```gdb
target remote | nc 127.0.0.1 3333
monitor reset halt
load
```

### 6.1 Breakpoints (like the IDE)

Set a breakpoint at a function:

```gdb
break main
break SystemInit
```

Set a breakpoint at a file:line:

```gdb
break src/main.c:3
```

Conditional breakpoint:

```gdb
break foo if x == 10
```

List breakpoints:

```gdb
info breakpoints
```

Delete a breakpoint:

```gdb
delete 1
```

Disable/enable:

```gdb
disable 1
enable 1
```

Run/continue until breakpoint:

```gdb
continue
```

### 6.2 Stepping (what you do all day)

Step over (like “Step Over”):

```gdb
next
```

Step into:

```gdb
step
```

Step out (finish current function):

```gdb
finish
```

Run until you return from the current function:

```gdb
until
```

### 6.3 Call stack + frames (CubeIDE Call Stack)

Show stack trace:

```gdb
backtrace
```

Move up/down the stack:

```gdb
up
down
```

Show current frame:

```gdb
frame
```

### 6.4 Variables, locals, and types

Print a variable:

```gdb
print myvar
p myvar
```

Print in hex:

```gdb
p/x myvar
```

Print address:

```gdb
p &myvar
```

Inspect locals / args:

```gdb
info locals
info args
```

Check a type:

```gdb
ptype MyStruct
```

### 6.5 Registers (CubeIDE Registers)

Show all general registers:

```gdb
info registers
```

Show a specific register:

```gdb
p/x $sp
p/x $pc
p/x $lr
```

Handy Cortex-M sanity checks:

* `$pc` changes as you step
* `$sp` points into SRAM

### 6.6 Memory view (CubeIDE Memory browser)

GDB’s memory examiner is `x/<count><format><size> <address>`

Sizes:

* `b` byte
* `h` halfword (16-bit)
* `w` word (32-bit)
* `g` giant (64-bit)

Formats:

* `x` hex
* `d` decimal
* `u` unsigned
* `c` char
* `i` instruction

Examples (copy/paste):

Read 16 words (32-bit) from SRAM base:

```gdb
x/16wx 0x20000000
```

Read 64 bytes from an address:

```gdb
x/64bx 0x20000000
```

Inspect the stack (32 words at SP):

```gdb
p/x $sp
x/32wx $sp
```

Inspect peripheral registers (example address):

```gdb
x/4wx 0x40020000
```

Disassemble instructions at PC:

```gdb
x/10i $pc
```

### 6.7 Watchpoints (data breakpoints)

Stop when a variable changes (hardware watchpoint, limited quantity):

```gdb
watch myvar
```

Stop when memory at an address is written:

```gdb
watch *(int*)0x20000010
```

List watchpoints/breakpoints:

```gdb
info breakpoints
```

### 6.8 Common “first bring-up” workflow

1. Connect and halt:

```gdb
target remote | nc 127.0.0.1 3333
monitor reset halt
```

2. Load firmware:

```gdb
load
```

3. Break at main and run:

```gdb
break main
continue
```

4. If it hardfaults immediately:

```gdb
backtrace
info registers
x/16i $pc
```

### 6.9 ELF inspection (verify what you built)

You can inspect the ELF *outside GDB* (often clearer):

Show ELF header:

```bash
arm-none-eabi-readelf -h build/target/firmware.elf
```

List sections:

```bash
arm-none-eabi-readelf -S build/target/firmware.elf
```

List symbols (functions/variables):

```bash
arm-none-eabi-nm -n build/target/firmware.elf | head
```

Check size contribution:

```bash
arm-none-eabi-size -A build/target/firmware.elf
```

Inside GDB, you can also do:

```gdb
info files
maintenance info sections
info functions main
```

### 6.10 Quality-of-life settings (optional)

These make interactive GDB nicer:

```gdb
set pagination off
set print pretty on
set print elements 0
```

---

## 7️⃣ Daily Operations Workflow

### Switch to embedded target

```bash
make -C target compdb
make switch-target
nvim .
```

Inside Neovim:

```vim
:LspRestart
```

### Build firmware

```bash
make -C target clean all
```

### Flash + debug

Terminal A:

```bash
openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
```

Terminal B:

```bash
gdb-multiarch build/target/firmware.elf
```

Inside GDB:

```gdb
target remote | nc 127.0.0.1 3333
monitor reset halt
load
break main
continue
```

---

## 8️⃣ Key Gotchas (Learned the Hard Way)

* `compile_commands.json` must exist **before** clangd works
* Bear records **only real compiles**
* `gdb-multiarch` TCP parsing may require `nc` pipe workaround
* HAL dramatically increases build complexity — avoid initially
* Linker script filename **must match exactly**

---

## 9️⃣ Philosophy

This workflow prioritizes:

* transparency over magic
* one tool per responsibility
* IDE independence
* understanding *why* things work

If you can answer:

> “What binary am I running, how was it linked, and how is it loaded?”

…you are doing embedded systems correctly.

