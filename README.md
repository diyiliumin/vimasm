# Vimasm

_A Turing-complete register-machine assembly dialect that runs inside Vim._

No plugins. No Vimscript.

Vimasm is a parasitic assembly language. Its runtime is Vim's Normal mode.
Its address space is the Vim buffer. Its program counter is the cursor's
current line. Its instruction fetch is `yy@0` — yank the line, replay it as
a macro.

Unlike prior proofs that Vim is Turing-complete (which simulate Turing
machines or interpret existing esolangs), Vimasm is a **register-based
assembly language** with an explicit instruction set, register model,
calling convention, stack, heap, and I/O sections.

- esolangs.org page: https://esolangs.org/wiki/Vimasm
- License: GPL v2

---

## Evolution

Vimasm was not designed in one sitting. It grew, stage by stage, from a
single half adder into a complete virtual machine. Each commit in this
repository corresponds to one stage in that growth.

Read `git log --oneline` from the bottom up, and you get the language's
development history.

| Stage | File | What it added |
|-------|------|---------------|
| 0 | `t.txt` | test `yy@0` macro execution |
| 1 | `bj.txt` | half adder |
| 2 | `qj.txt` | full adder |
| 3 | `alu.txt`, `alu_more.txt` | ALU, 10 operations |
| 4 | `asm.txt`, `asm_jnc.txt`, `asm_jnc_fix_if.txt` | assembler + jump-no-carry |
| 5 | `asm_cmt_tab.txt` | comments + tab indentation |
| 6 | `asm_bout.txt`, `asm_jz_jmp.txt`, `asm_varabled.txt` | jmp, jz, decimal support |
| 7 | `asm_call_ret.txt` | call / ret |
| 8 | `asm_pop_push.txt` | stack push / pop |
| 9 | `asm_heap.txt` | heap + store / load |
| 10 | `asm_insert.txt` | insert string into heap |
| 11 | `asm_auto_set_addr_for_call*.txt` | auto address for call |
| 12 | `asm_auto_set_addr_for_call_bk_d_buildin_for_slow_show.txt` | slow-show debug build |

The assembler relies on the ALU. The full machine is `asm_insert.txt` (or
the latest `asm_auto_set_addr_for_call*` build, if you want call/ret with
automatic return-address handling).

---

## Usage

1. Open any `.txt` file with a **plain, unconfigured Vim** (no plugins, no vimrc needed).
2. Read the usage instructions written inside the file.
3. For the latest full build:
   - `127Gyy@0` to generate the binary-to-decimal lookup table
   - wait for the red error message
   - `135Gyy@0` to run the test program (takes about a minute)
4. A red Vim error message means "instruction completed" — this is intentional.
5. To write your own program, edit the region below `please write asm below here`.

If you see no red message but the program stops, it has derailed. Either
your syntax does not match the assembler's strict format, or you hit an
untested edge case.

---

## Instruction Set

| Opcode | Semantics |
|--------|-----------|
| `mov rX,YYYY` | write YYYY into register rX |
| `add rX,rY` | rX = rX + rY |
| `sub rX,rY` | rX = rX - rY |
| `and rX,rY` | rX = rX AND rY |
| `or rX,rY` | rX = rX OR rY |
| `xor rX,rY` | rX = rX XOR rY |
| `not rX` | rX = NOT rX |
| `shl rX` | rX = rX << 1 |
| `sar rX` | rX = rX >> 1 (arithmetic) |
| `slr rX` | rX = rX >> 1 (logical) |
| `cmp rX,rY` | compare rX and rY, set flags |
| `jmp __flag` | jump to flag |
| `jz __flag` | jump to flag if zero flag is set |
| `jnc __flag` | jump to flag if carry flag is clear |
| `call __aim,__ret` | write return address, jump to aim |
| `ret` | return to written address |
| `push rX` | push rX onto stack |
| `pop rX` | pop stack into rX |
| `load rX,[rY]` | load memory at address rY into rX |
| `store [rX],rY` | store rY into memory at address rX |
| `malloc rX` | resize heap |
| `free rX` | shrink heap |
| `insert rX,string` | insert string into heap |
| `out rX` | output rX as binary to STDOUT |
| `dout rX` | output rX as decimal to STDOUT |
| `end` | halt |

---

## Memory Model

- **Registers** — fixed lines in the buffer, addressed by `G` and line number.
- **Stack** — a dedicated `STACK` section, pushed and popped manually.
- **Heap** — a `HEAP` section, resized by `malloc` and `free`.
- **I/O** — a `STDOUT` section, written by `out` and `dout`.
- There is no separate data section: every value is a plain text line.

---

## Control Flow

- Flags are defined with `__<space>name` and referenced with `__name`.
- The program starts at the last `__start`.
- Comments begin with `;;`.
- Indentation must use tabs.
- A Vim red error message is used as the "instruction completed" signal.

---

## Computational Class

Vimasm is Turing-complete: it has unbounded memory (the buffer can be
extended), conditional branching, and a call stack.

---

## Documents

- `how_does_this_work.md` — the author's own description of how the ALU works.
- `vim_vm_principle_analysis.md` — a third-party analysis of the assembler,
  written by reverse-engineering the code. Included for reference.

---

## License

GPL v2. See `LICENSE`.
