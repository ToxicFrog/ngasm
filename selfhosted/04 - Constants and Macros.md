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

### Registers, memory, and literals

Registers are designated with the letters `A` or `D`. The letter `M` denotes the
memory cell pointed to the current value of the A register.

Numeric literals can be written in four different formats:

- *Decimal literals* consist of a sequence of the digits 0-9 and are treated as
  an unsigned base 10 number.
- *Hexadecimal literals* consist of a `$` followed by a sequence of the digits
  0-9, a-f, and A-F and are treated as an unsigned base 16 number.
- *Character literals* consist of a `'` followed by a single character and are
  treated as the 7-bit ASCII value of that character.
- *Relative addresses* are decimal literals prefaced with a `+` (for a jump
  forward) or a `-` (for a jump backwards); this will compile as the address of
  the instruction itself, plus or minus the given value. It is safe to use in
  macros.

Thus, the following three instructions are equivalent:
```
@ 58
@ $3A
@ ':
```

Note that support for octal literals was removed in this version.

### Labels

A label associates a name with a specific address in ROM. A label definition
must occupy its own line (you cannot put a label and instruction on the same
line); it starts with `:` and runs until end of line.

```
:MyLabel  ; defines a label for this address
```

The label can be used in a load immediate instruction to load A with the address
where it was defined. It can be used even in code that precedes its definition
in the file.

Note that the leading `:` is part of the label name, and must be used when
referencing it:

```
@ :MyLabel  ; loads A with the address bound to MyLabel
```

### Named Constants

Unlike a label, a constant associates a name with a user-supplied value. This
value can be any numeric literal.

A constant definition starts with a `#` or `&`, followed by the rest of the name,
an `=`, and then the value, e.g.

```
&cat_ptr = 2
#eol = $0A
#at = '@
```

By convention, constants referring to memory addresses start with `&` while
constants referring to non-memory values such as character codes, loop iteration
counts, etc start with `#`, but this is a convention only and is not enforced.

### Macros

A macro defines a named sequence of assembly instructions that can be replayed
at will. When a macro is referenced, the instructions making it up are inserted
into the emitted ROM in place of the macro reference.

Note that unlike constants or labels, the macro definition *must* appear before
its use.

Note also that macros are not functions; the macro body is inlined into the
output code.

A macro definition has the form:

```
[macro-name
  instructions...
]
```

And a macro reference:

```
~macro-name
```

#### Macro Arguments

Arguments can be passed to a macro by appending them to the macro call with
commas:

```
~macro,0,1,2,3
```

You can use anything you would use with @ as arguments, including numeric and
character literals, labels, and named constants.

Within the macro definition, up to ten arguments can be accessed by prefacing
a single decimal digit with `%`:

```
[macro
  @ %0
]
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
