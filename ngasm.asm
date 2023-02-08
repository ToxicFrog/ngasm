#### Assembler, phase 1 ####
#
# This is intended to read a very stripped down, easy to parse version of the
# nandgame asm: M instead of *A, very little error checking, <=> to directly set
# the jump flags instead of Jxx mnemonics, etc.
#
# It is written in nandgame asm and is meant to be assembled by the nandgame
# in-browser assembler to start the bootstrap process. In a real-world situation
# where I didn't have an existing computer to cross-assemble on, I'd probably
# write out the program on paper, then hand-assemble it into machine code and
# enter the machine code on toggle switches, punch cards, paper tape, mask ROM,
# etc. (Or, since hand-assembling is very slow, get a bunch of friends to help
# and have each of us assemble one function.) Once it's up and running it can
# then be used to assemble later versions of itself.
#
# This version does not support macros or labels, but I think it won't actually
# be usefully self-hosting until it has label support, so probably I'll build
# this version in nandgame, test it to make sure it generates the right machine
# code, then upgrade it to handle labels before I start feeding it to itself.
#
#### The Language ####
#
# The language it assembles is based on the nandgame assembler syntax, but
# stripped down to make it easier to parse and, in particular, to make it
# possible to parse by looking just at the next character, without needing to
# read in entire words. It also has effectively no error checking, so things
# like trying to load an 18-bit number or asking it to compute D+D will generate
# incorrect code rather than failing.
#
# Instructions have two forms. Load immediate instructions start with @:
#   @12345
# And load the given 15-bit literal into A. The number is given in octal and can
# thus be up to 5 digits long.
#
# Compute instructions have the format. Fields in <> are mandatory. Fields in
# [] are optional.
#   [destination] = <operand> <operator> [operand] [<jump bits>]
# The destination is any combination of A, D, and M and can be omitted entirely.
# The = is mandatory and separates the destination from the expression.
# The first operand can be A, D, M, or 0.
# The operator is one of: +-&|^!
# The second operand can be A, D, or M; it can also be + or - to generate a unary
# increment or decrement instruction. If the operator is ! the second operand is
# omitted entirely. So these are all valid:
#
#   ADM = D+A
#   A = D++
#   M = 0-D
#   D = M!
#
# The jump bits are optional. They consist of any combination of < for JLT, =
# for JEQ, or > for JGT. These directly correspond to the lt, eq, and gt bits
# in the opcode.
#
# Note that the =, first operand, and operator are mandatory, so an unconditional
# jump must be written as a no-op ALU instruction followed by a full set of jump
# bits:
#
#   = 0!, <=>
#
# Spaces in the input are ignored, so "=0!,<=>" and "= 0! , <=>" are equivalent.
# The ADM in the destination field and the <=> in the jump field can appear in
# any order.
#
#### Program Structure ####
#
# The assembler is a state machine. In practice this means that each "state" is
# a procedure which must:
#  (1) examine the next character from the input file;
#  (2) make changes to the opcode being generated based on that character; and
#  (3) decide what the next state to run is.
# So, for example, the ReadDestination state reacts to an input of "A", "D", or
# "M" by setting the a, d, or m bits in the opcode and staying in the same state,
# or the input "=" by leaving the opcode unchanged but choosing ReadFirstOperand
# as the next state, since that's the next part of the instruction after the =.
#
# This is driven by the MainLoop procedure, which is what actually reads the
# bytes from the file. It reads and discards spaces until it finds a non-space
# character.
#
# If the character is ; it has found a comment. It sets the *in_comment flag,
# which causes it to ignore all characters until the next newline.
#
# If that character is a newline, it outputs an opcode; it operates on a strict
# one line = one opcode policy, so blank/comment lines will emit no-op instructions.
# Whatever is in the "under construction opcode" buffer is what gets written.
# After doing this, it resets the opcode to 0x8000, clears the *in_comment flag,
# and resets the current state to NewLine.
#
# If it finds anything else, it leaves the character in *char and calls the
# current state, which is pointed to by the *state global. That procedure is
# then responsible for updating *opcode and, if it decides a new state needs to
# be selected, updating *state to point to it.
#
#### State Diagram ####
#
# This is a breakdown of all the states in the program. It is meant as a quick
# reference, not a detailed explanation of the internals of each state.
# Each state has an implied "if it sees something here it doesn't recognize,
# abort the program" built into it. This is the only concession to error handling.
#
# ->State means "set the next state for the main loop to call to State". Some
# states may also "then call State", meaning to run it immediately without
# returning to the main loop, allowing that state to look at the same character
# this one was looking at.
#
# LineStart:
#   @: clear ci bit, ->LoadImmediate
#   else: ->Destination, then call Destination
# LoadImmediate:
#   0-7: add digit to opcode
# Destination:
#   ABM: set a, b, or m
#   =: ->LHS
# LHS:
#   A: set sw, ->Operator
#   D: ->Operator (the default is D so we don't need to change the opcode)
#   M: set sw and mr, ->Operator
#   0: set zx, ->Operator
# Operator:
#   +-&|^: set u, op1, and op0 bits accordingly, ->RHS
#   !: set bits to 011, ->Jump
# RHS:
#   A: ->Jump
#   D: set sw, ->Jump
#   M: set mr, ->Jump
#   +-: set op0 (so add turns into inc and sub turns into dec), ->Jump
# Jump:
#   <: set lt
#   =: set eq
#   >: set gt
#

#### Program Code ####

# Globals
# Most recently read character
DEFINE char 0
# Opcode under construction
DEFINE opcode 1
# True if we are in read-and-discard-comment mode
DEFINE in_comment 2
# Pointer to current state
DEFINE state 3

# Memory mapped IO
# input file is mapped at 0x7FF0, so the bytewise channel is at 0x7FF1
DEFINE stdin_status 0x7FF0
DEFINE stdin 0x7FF1
# output file is mapped at 0x7FF8, so the wordwise channel is at 0x7FFA
DEFINE stdout 0x7FFA

## Main loop and helpers ##

# Bootup. Runs at start and at the beginning of each line to initialize
# the various globals.
  NewInstruction:
# Set opcode to 0x8000, which is a no-op (computes D&A and discards it).
# We do this by computing 0x4000+0x4000 since we can't express 0x8000 directly.
A = 0x4000
D = A
D = D+A
A = opcode
*A = D
# Clear the in_comment flag
A = in_comment
*A = 0
# Set the current state to NewLine, the start-of-line state
A = LineStart
D = A
A = state
*A = D
# Fall through to Mainloop.

# Core loop.
# This reads input byte by byte. Spaces and comments are discarded, newlines
# trigger opcode emission, everything else is passed to the current state.
  Mainloop:
# Read input status word, if end of file, end program.
A = stdin_status
D = *A
A = Exit
D; JEQ
# Read next byte of input and stash it in char
A = stdin
D = *A
A = char
*A = D
# If it's a newline, run the end-of-line routine.
A = 0x0A
D = D - A
A = EndOfLine
D;JEQ
# If we're in a comment, skip this character
A = in_comment
D = *A
A = MainLoop
D;JNE
# Also skip spaces
A = char
D = *A
A = 0x20
D = D - A
A = Mainloop
D; JEQ
# If it's a start-of-comment character, run CommentStart to set the in_comment flag
A = char
D = *A
A = 0x3B
D = D - A
A = CommentStart
D; JEQ
# At this point, it's not a newline, it's not a space, it's not the start or
# interior of a comment, so it should hopefully be part of an instruction.
# Call the current state to deal with it. It will jump back to MainLoop when done.
A = state
A = *A
JMP

## Helper procedures for Mainloop. ##

# Called when it sees the start-of-comment character. Sets the in_comment flag
# and ignores the input otherwise.
  CommentStart:
A = in_comment
*A = 1
A = Mainloop
JMP

# Called to output the opcode being generated, at the end of a line. Jumps to
# NewInstruction when done to reinitialize the globals.
  EndOfLine:
A = opcode
D = *A
A = stdout
*A = D
A = NewInstruction
JMP

## State definitions ##

# The base state that we get reset to at the end of every line.
# It looks at the first character of the line and if it's an @, transitions to
# LoadImmediate.
# Anything else causes a transition to Destination, to read the A/D/M bits at
# the start of a compute instruction.
  LineStart:
# If it's not an @, we're looking at a compute instruction
A = char
D = *A
A = 0x40
D = D-A
A = LineStart_ComputeInstruction
D;JNE
# If we get here it's an @, so a load immediate -- clear the high bit in the
# opcode and set LoadImmediate as the state to process the rest of the line.
A = opcode
*A = 0
A = LoadImmediate
D = A
A = state
*A = D
A = Mainloop
JMP
  LineStart_ComputeInstruction:
# It's the start of a compute instruction. The first character is already going
# to be significant, so we need to set the current state to Destination and then
# jump to Destination rather than Mainloop, so we don't skip the current char.
A = Destination
D = A
A = state
*A = D
A = Destination
JMP

# The state for reading the number in a load immediate instruction.
# The number is octal, so for each digit, we multiply the existing number by
# 8 (by repeated doubling via self-adding) and then add the new digit to it.
  LoadImmediate:
# Start by making room in the opcode
A = opcode
D = *A
*A = D+*A
D = *A
*A = D+*A
D = *A
*A = D+*A
# Opcode has now been multiplied by 8, add the next digit.
A = char
D = *A
# Subtract '0' to get a value in the range 0-7
# or out of the range if the user typed in some sort of garbage, oh well
A = 0x30
D = D-A
A = opcode
*A = D+*A
A = Mainloop
JMP

  Destination:
# not implemented
A = Mainloop
JMP

# Destination:
#   ABM: set a, b, or m
#   =: ->LHS
# LHS:
#   A: set sw, ->Operator
#   D: ->Operator (the default is D so we don't need to change the opcode)
#   M: set sw and mr, ->Operator
#   0: set zx, ->Operator
# Operator:
#   +-&|^: set u, op1, and op0 bits accordingly, ->RHS
#   !: set bits to 011, ->Jump
# RHS:
#   A: ->Jump
#   D: set sw, ->Jump
#   M: set mr, ->Jump
#   +-: set op0 (so add turns into inc and sub turns into dec), ->Jump
# Jump:
#   <: set lt
#   =: set eq
#   >: set gt
#
