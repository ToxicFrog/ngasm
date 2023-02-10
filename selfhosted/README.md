This directory holds the various stages of the self-hosted toolchain. This is
visible in the git history, but this displays it in a somewhat more convenient
manner.

In general, it follows a pattern where even-numbered versions implement new
features (starting at stage 0 which implements the first version of the
assembler itself), while odd-numbered versions refactor or completely rewrite
the assembler to take advantage of those new features without changing the actual
functionality of the assembler.

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

It's checked in two ways:
- comparing its output to the stage 0 ROM produced by the nandgame assembler. This
  is an imperfect comparison because of the no-ops; stripping the no-ops before
  comparing helps, but not as much as one might think, because the nandgame assembler
  also treats the unused bits in the instruction differently (setting some of them
  to 1 on some instructions) and, of course, all the jump targets are different.
  It can still rule out egregious errors like generating the wrong number of
  instructions or dramatically different values for non-jump-target constants,
  however.
- comparing the ROM image produced by running the stage 0 assembler on the stage
  1 source code, vs. the running the stage 1 assembler on itself. These should
  be identical; this doesn't completely rule out bugs but it's a good sign. And
  they are, indeed, identical in every byte.

In the process of making this translation, I also found a few bugs in the stage 0
code -- two places where it jumped to the wrong label, one where it was setting
the wrong bit in the opcode, and one where it was checking for the wrong input
character. In the interests of versimilitude I fixed these by editing the .hex
file for the stage 0 ROM by hand rather than by re-assembling it with the nandgame
assembler. :)