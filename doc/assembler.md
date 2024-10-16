# NANDgame IR

This documents the instruction format for NANDgame and NANDgame assembly.

## Terminology

A - the A register
D - the D register
M - the contents of memory at the address given by the A register
*A - synonym for M, supported for nandgame compatibility

## Format

Instructions are fixed-width 16-bit words with the following layout:

```
Mask  Bit  Name   Meaning
8000  F    ci    If 0, load immediate. Otherwise perform computation.
4000  E    -     unused
2000  D    -     unused
1000  C    mr    if set, ALU inputs are [D, M] rather than [D, A]
0800  B    -     unused
0400  A    u     if 1, ALU does math. If 0, logic.
0200  9    op1   ] ALU ops. For math: 00 = +, 01 = inc, 10 = -, 11 = dec
0100  8    op0   ] For logic: 00 = and, 01 = or, 10 = xor, 11 = not.
0080  7    zx    If 1, first operand to ALU is 0. This is applied after sw and m.
0040  6    sw    If 1, ALU gets [A, D] instead of [D, A] as inputs.
0020  5    a     Write result to A.
0010  4    d     Write result to D.
0008  3    m     Write result to M.
0004  2    lt    Jump if result <0.
0002  1    eq    Jump if result =0.
0001  0    gt    Jump if result >0.
```

There are two families of instructions: load-immediate, and compute-and-jump. These are determined by the first bit; if
it is 0, it is a load-immediate instruction, and the entire instruction is copied without modification into A.

Computation instructions are hard to divide into more specialized families; they all basically have the form "feed some
inputs through the ALU, optionally store the result somewhere, then optionally jump based on the result".

### ALU inputs

The bits controlling the inputs to the ALU may be the most confusing. Rather than having two bitfields that directly
control inputs, the input to the ALU defaults to `[D, A]`. This is then permuted by bits C, 7, and 6, in the following
manner (and *in this order*):

- if C (mr) is set, the second operand is loaded from memory, making the operands `[D, M]`
- if 6 (sw) is set, the operands are swapped, making them `[A, D]`
- if 7 (zx) is set, the first operand is replaced with 0, making them `[0, A]`

These can of course be combined, so for example if both `mr` and `zx` are set the operands are `[0, M]`. If both `sw`
and `zx` are set, the operands are swapped *before* one of them is zeroed.

### ALU operations

The ALU explicitly supports eight operations, controlled by the `u`, `op1`, and `op0` bits: bitwise and, or, xor, and not,
addition and subtraction, and increment and decrement. Not, increment, and decrement are unary operations.

It also supports a number of implied operations:
- by setting `zx` to 1 and the operation to `101` (inc), `111` (dec), or `000` (and), it can produce the constants 1, -1,
  and 0 respectively
- by setting `zx` to 1 and the operation to `110` (sub), it can do arithmetic negation on its second operand (which,
  through the use of `mr` and `sw`, can be any register or memory).
- by setting `zx` to 1 and the operation to `001` (or), it performs the identity function, which is how move operations
  are performed; `D = A` is internally encoded as `D = 0 | A`.

### Destination

Bits 5-3 determine where, if anywhere, the output of the ALU is stored. These bits can be set in any pattern:

```
Bits  Mnemonic
 000  none; result is discarded
 001  *A =
 010  D =
 011  D,*A =
 100  A =
 101  A,*A =
 110  A,D =
 111  A,D,*A =
```

Some assemblers support `M` as a synonym for `*A`.

### Jumps

Bits 2-0 control whether a jump occurs. If `000`, no jump occurs. If `111`, the jump is unconditional. Other patterns
are ORed together, so `110` is "jump if lt or eq".

If a jump occurs, the destination is the value held in A at the start of the clock cycle; in particular this means that
the following code:

```
A = loop
A = exit; JMP
```

will jump to `loop`, not `exit`.

These are the mnemonics supported by the assembler:

```
Bits  Mnemonic
 000  none
 001  JGT
 010  JEQ
 011  JGE
 100  JLT
 101  JNE
 110  JLE
 111  JMP
```

Load-immediate instructions have the MSB set to 0, and the remaining bits arbitrary. The entire opcode is written to
A. In effect this means A can be loaded with any 15-bit number.

Compute-and-jump instructions have the following behaviour:
- the ALU is loaded with two operands. By default this is [D A] but various bits in
  instruction affect this.
- the result is computed, and stored in zero or more of A, D, and *A
- if a jump is specified, program execution jumps to the address that was stored
  in A at the start of this clock cycle (NOT the address that was just written to it)

ci - - * - u op1 op0 zx sw a d *a lt eq gt

