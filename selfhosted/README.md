This directory holds the various stages of the self-hosted toolchain. This is
visible in the git history, but this displays it in a somewhat more convenient
manner.

## 00 - Simple Assembler (nandgame syntax)

This is the first version of the assembler. It's designed to be straightforward
and easy to follow, not necessarily compact, efficient, or easy to upgrade. This
version was written in the syntax understood by the in-browser assembler used by
[NANDgame](https://www.nandgame.com/), which is not the same syntax it
understands itself -- this let me use nandgame to assemble it, rather than doing
what I would have needed to do in a true "self hosting from scratch" situation,
i.e. write it out on paper and assemble it to machine code using a pencil and a
copy of the processor reference manual.

## 01 - Simple Assembler (ngasm syntax)

This is a 1:1 translation of the above into the syntax that it itself understands.
This is thus the first version of the assembler that you can feed to itself.

It is fairly hard to follow due to the lack of support for defines and labels; the
overall program structure and algorithm are identical to the nandgame-syntax
version, so I recommend reading that instead to understand how it works.

Note that the output hex file is much larger than 00, because the nandgame assembler
skips blank and comment lines, while the simple assembler (to keep it simple)
outputs no-op instructions for them.
