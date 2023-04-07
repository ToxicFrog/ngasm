# ngasm
## A self-hosting language for the NANDgame core

[NANDgame](https://nandgame.com) is a cool puzzle/educational game where you build a computer from scratch, starting with individual logic gates and ending with a basic macro assembler. It's a lot of fun, but it also kind of skips over the whole process of bootstrapping the language -- as does the book it's inspired by, *From NAND to Tetris*.

I've [built languages before](https://github.com/ToxicFrog/avr-bits/tree/notforth) but I've never made a fully self-hosting one, or bootstrapped one from scratch on unfamiliar hardware, so I decided to do that as a learning exercise and document the process.

I started with an extremely simple, bare-bones assembler of about 400 LOC. With no error handling, and a syntax designed to be easy to parse at the expense of everything else, it wasn't a *good* language -- but the assembler was simple enough that one could plausibly hand-assemble it. (Although, in the interests of saving time, I actually used the assembler built into NANDgame for this step.) Once I had that, I had a basic self-hosting assembler and could use it to build on itself, adding labels, named variables, relative jumps, macros, a call stack, and so forth. The ultimate goal, although it's not there yet, is to build a simple Forth-like language.

## Current State

Stage 4, which adds macros, named variables, an improved numeric literal parser, and better error handling, is complete. The next two stages are:
- Stage 5: refactor the current compiler to use these features without changing its behaviour.
- Stage 6: replace the parser outright and make the language more readable; generate smaller binaries.

## Repo Contents

The contents of the repo are divided into various subdirectories, most of which
contain more detailed READMEs specific to their contents:
- [`selfhosted`](./selfhosted/) contains a history of the different stages of
  the self-hosting compiler. Each stage has a markdown file describing the
  behaviour of that stage, and an assembly file containing the source code.
- [`bin`](./bin/) contains the ROM images corresponding to the different stages,
  in `xxd` format.
- [`vm`](./vm/) contains a Lua implementation of the nandgame CPU. It supports
  memory-mapped peripherals and has some primitive debugging features.
- [`solutions`](./solutions/) contains solutions to some of the NANDgame
  puzzles, included here as a reference.
- [`stable`](./stable/) and [`next`](./next/) contain symlinks and temporary
  files used in the development process.
