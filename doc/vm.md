# VM behaviour and design

The VM has the following components:
- A register (16 bits)
- D register (16 bits)
- I register (internal, holds the current instruction)
- P register (internal, points to the next instruction in ROM)
- ROM (64k, not directly accessible)
- RAM (32k, accessible via the A register)

The memory map is thus (all addresses in hex). Lines marked with a `*` are not
present in the nandgame spec.

```
0000-00FF     zero page memory, typically used for the HLL runtime
     0000     SP, stack pointer
     0001     ARGS, pointer to first argument of current stack frame
     0002     LOCALS, pointer to first local of current stack frame
     0006     RETVAL, temporary used by call/return
0100-01FF     stack, grows upwards from 0100; may be larger
0200-3FFF     program memory; starts wherever the stack ends
4000-5FFF     SCREEN; 512x256 bitmapped display, 1 word = 16 pixels; may be smaller
6001          NET; bit 0 is data, bit 1 is sync; not implemented
7FFD          WSTDIO; read and write words from simulator input/output
7FFE          BSTDIO; read and write bytes; bites 0xFF00 are always 0 on read, ignored on write
7FFF          ROBOT; not implemented
```

The starting inputs are:
- a ROM image; mandatory; this is the program code
- a memory image; optional; if absent all memory is 0-initialized
- an input source; optional; if present reads from WSTDIO or BSTDIO will return successive words/bytes from this
- an output sink; optional; if present writes to WSTDIO or BSTDIO will write words/bytes to this

The execution model is:
- fetch instruction from `ROM[P]` into `I`
- inc `P`
- if load immediate, copy `I` to `A` and resume from start
- decode instruction:
  - determine operands
  - compute result
  - if any jump bits are set and result meets requirements: copy `A` to `P`
  - if any write bits are set: write result to `M`, `A`, and/or `D`; don't forget to write to M before A!
- resume from start
