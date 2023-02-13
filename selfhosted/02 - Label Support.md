# ngasm syntax (stages 2 and 3)

This document describes the behaviour of, and language understood by, the
assembler program.

## Behaviour

The assembler requires the source file mapped as a readable iostream at $7FF0,
and the destination file mapped as a writeable iostream at $7FF8.

It produces no diagnostic output; on success the entire ROM image is written, in
big-endian binary format, to the destination file. (Piping it through `xxd` to
get a readable hex dump is recommended.)

One word of output is written per input line; lines that contain no code will
result in no-op instructions being written.

On error, it writes a single zero byte to the output file and exits. Since a
well-formed ROM will always have an even number of bytes in it, this means you
can detect that a compilation error occurred if the size of the output file is
odd, and where in the file it occurred by how long the file is.

## Language

The language is line-oriented; each line contains either a single instruction
(and optionally comments), or no instruction (comments or blank line).

It is case-sensitive; `A` and `a` are not the same character.

### Whitespace and comments

The space character ` ` is understood as whitespace, and ignored completely. The
semicolon `;` begins a comment, which runs to the end of the line; comments can
be on a line by themselves or at the end of a line following an instruction. The
newline `\n` ends a line (and thus an instruction) and begins a new one. Other
whitespace, such as tabs, has *undefined effects*.

### Registers, memory, and constants

Registers are designated with the letters `A` or `D`. The letter `M` denotes the
memory cell pointed to the current value of the A register.

Numeric constants are written in octal (base 8).

### Labels

A label associates a name with a specific address in ROM. A label definition
must occupy its own line (you cannot put a label and instruction on the same
line); it starts with `:` and runs until the first `.`, e.g.

```
:MyLabel.  ; defines a label for this address
```

The label can be used in a load immediate instruction to load A with the address
where it was defined. It can be used even in code that precedes its definition
in the file.

Note that both the leading `:` and the trailing `.` are part of the label name,
and must be used when referencing it:

```
@ :MyLabel.  ; loads A with the address bound to MyLabel
```

### Instruction format

There are two kinds of instructions: load immediate and computation.

#### Load Immediate Instructions

Load immediate instructions consist of a `@` followed by either a label or up to
five octal digits.

In the former case, the ROM address associated with that label is loaded into A;
in the latter case, the literal value provided is.

#### Computation instructions

Computation instructions look like (optional parts in `[...]`):
```
  [destination] '=' lhs operator rhs [jump]
```

Where:
- *destination* is any combination of the letters `A`, `D`, and `M`
- *lhs* is `A`, `D`, `M`, or `0`
- *operator* is `+`, `-`, `&`, `|`, `^`, or `!`
- *rhs* is `A`, `D`, `M`, or `1`, and must be omitted if the operator is `!`
- and *jump* is any combination of the characters `<`, `=`, and `>`

Note a number of restrictions: the left and right hand operators are mandatory
except for the unary negation operator '!'; 0 can appear only on the LHS and
1 only on the RHS; the leading '=' is required even if the result is not going
to be saved aynwhere; the expression is required even if it's not used for
anything (e.g. in an unconditional jump).

This means, in particular, that to store a 0 constant you must write `0 & A`,
to store a 1 or -1 constant you must write `0 + 1` or `0 - 1`, and to get the
value of a register or memory location you must write `0 | D` (or similar); you
cannot write `D = M` as you would in nandgame but must instead write `D = 0 | M`.

It also means that to express an unconditional jump, you must write `= D-A <=>`
or similar. Throughout the stage 1 code I use `= 0|D <=>` for reasons that
probably made sense at the time.

There is also no sanity checking to ensure the instruction makes semantic sense.
In particular, it is the reponsibility of the programmer to adhere to the
constraint that D can appear only on one side of the expression, and A or M only
on the other side; if you ask it for `D + D` or `A + M` it will do *something*,
but not what you asked for.
