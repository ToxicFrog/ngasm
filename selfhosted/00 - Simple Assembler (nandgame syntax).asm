#### Assembler, stage 0 ####
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
# The second operand can be A, D, or M; it can also be 1 to generate a unary
# increment or decrement instruction. If the operator is ! the second operand is
# omitted entirely. So these are all valid:
#
#   ADM = D+A
#   A = D+1
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
DEFINE stdout_bytes 0x7FF9
DEFINE stdout 0x7FFA

################################################################################
## Main loop and helpers                                                      ##
################################################################################

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

################################################################################
## LineStart state                                                            ##
################################################################################

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

# It's the start of a compute instruction. The first character is already going
# to be significant, so we need to set the current state to Destination and then
# jump to Destination rather than Mainloop, so we don't skip the current char.
  LineStart_ComputeInstruction:
A = Destination
D = A
A = state
*A = D
A = Destination
JMP

################################################################################
## LoadImmediate state                                                        ##
################################################################################

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

################################################################################
## Destination state                                                          ##
################################################################################

# State for reading the optional A, D, and M at the start of an instruction,
# designating the destination(s) for the computed values.
  Destination:
# Check for =, which sends us to the next state (LHS)
A = char
D = *A
A = 0x3D
D = D-A
A = Destination_Finished
D;JEQ
# Check for A.
A = char
D = *A
A = 0x41
D = D-A
A = Destination_A
D;JEQ
# Check for D.
A = char
D = *A
A = 0x44
D = D-A
A = Destination_D
D;JEQ
# Check for M.
A = char
D = *A
A = 0x4D
D = D-A
A = Destination_M
D;JEQ
# None of the above branches worked, so we're looking at something we don't
# understand and should abort the program.
A = Error
JMP

# We read an =, so set up the state transition.
  Destination_Finished:
A = LHS
D = A
A = state
*A = D
A = Mainloop
JMP

# The next three short procedures all set up D with the correct bit to set in
# the instruction and then jump to Destination_SetBits, which does the actual
# modification of the opcode.
  Destination_A:
A = 0x0020
D = A
A = Destination_SetBits
JMP
  Destination_D:
A = 0x0010
D = A
A = Destination_SetBits
JMP
  Destination_M:
A = 0x0008
D = A
# fall through
# The bit we want is in D, so bitwise-or it into the opcode
  Destination_SetBits:
A = opcode
*A = D | *A
A = Mainloop
JMP

################################################################################
## LHS operand state                                                          ##
################################################################################

# State for reading the left-hand side of the ALU expression.
# This is a one-character state, so it processes whatever's in char and then
# immediately transitions to the Operator state.
# The LHS defaults to D, which requires no action. A or M require setting the
# sw bit; M additionally requires setting the mr bit. 0 requires setting the zx
# bit; it may also require setting sw or mr depending on what the RHS is, but
# that will be handled by the RHS state.
  LHS:
# Check for A.
A = char
D = *A
A = 0x41
D = D-A
A = LHS_A
D;JEQ
# Check for D.
A = char
D = *A
A = 0x44
D = D-A
A = LHS_Done
D;JEQ
# Check for M.
A = char
D = *A
A = 0x4D
D = D-A
A = LHS_M
D;JEQ
# Check for 0.
A = char
D = *A
A = 0x30
D = D-A
A = LHS_Z
D;JEQ
# None of the above branches worked, so we're looking at something we don't
# understand and should abort the program.
A = Error
JMP

# Operand is 0, set the zx bit.
  LHS_Z:
A = 0x0080
D = A
A = LHS_SetBits
JMP

# Operand is M, set the mr bit and fall through the LHS_A to set the sw bit.
  LHS_M:
A = 0x1000
D = A
# fall through to LHS_A.

# Operand is A, set the sw bit.
  LHS_A:
A = 0x1000
# Use | here so that the fallthrough case from LHS_M works as expected.
# If we came from LHS proper, D is guaranteed to be zero because we JEQ'd.
D = D|A

# D contains some pile of bits. Set them in the opcode.
  LHS_SetBits:
A = opcode
*A = D | *A
# fall through
  LHS_Done:
A = Operator
D = A
A = state
*A = D
A = Mainloop
JMP

################################################################################
## Operator state                                                             ##
################################################################################

# State for reading the ALU operator.
# It understands the following binary operations, with the following bit patterns:
#  +    add   0400
#  -    sub   0600
#  &    and   0000
#  |    or    0100
#  ^    xor   0200
#  !    not   0300
# inc and dec are handled in the RHS state.
  Operator:
# add
A = char
D = *A
A = 0x2B
D = D-A
A = Operator_Add
D;JEQ
# sub
A = char
D = *A
A = 0x2D
D = D-A
A = Operator_Sub
D;JEQ
# and
A = char
D = *A
A = 0x26
D = D-A
A = Operator_And
D;JEQ
# or
A = char
D = *A
A = 0x7C
D = D-A
A = Operator_Or
D;JEQ
# xor
A = char
D = *A
A = 0x5E
D = D-A
A = Operator_Xor
D;JEQ
# not
A = char
D = *A
A = 0x21
D = D-A
A = Operator_Not
D;JEQ
# None of the above branches worked, so we're looking at something we don't
# understand and should abort the program.
A = Error
JMP

# Helpers for the various ALU operations. Same deal as LHS here, they
# set the bits needed in D and then jump to SetBits to actually move
# them into the opcode.
  Operator_Add:
A = 0x0400
D = A
A = Operator_SetBits
JMP
  Operator_Sub:
A = 0x0600
D = A
A = Operator_SetBits
JMP
  Operator_And:
D = 0
A = Operator_SetBits
JMP
  Operator_Or:
A = 0x0100
D = A
A = Operator_SetBits
JMP
  Operator_Xor:
A = 0x0200
D = A
A = Operator_SetBits
JMP

# This gets special handling because we need to skip the second operand
# entirely, since not is a unary operation.
  Operator_Not:
A = 0x0300
D = A
A = opcode
*A = D | *A
A = Jump
D = A
A = state
*A = D
A = MainLoop
JMP

# Write bits to opcode, set next state to RHS, return to main loop.
  Operator_SetBits:
A = opcode
*A = D | *A
A = RHS
D = A
A = state
*A = D
A = Mainloop
JMP

################################################################################
## RHS operand state                                                          ##
################################################################################

# State for the right-hand operand. This is basically the same as the
# state for the left-hand, except it understands 1 (as meaning "set the
# op0 bit to turn add/sub into inc/dec") rather than 0, and of course the
# bit patterns it emits are different.
# Note that there is no consistency checking with what LHS ingested, so
# you can ask it for invalid operations like "D&1" and it will generate
# something that isn't what you asked for -- in the above case D|A.
  RHS:
# Check for A. This is the default case, so we set no bits.
A = char
D = *A
A = 0x41
D = D-A
A = RHS_Done
D;JEQ
# Check for D.
A = char
D = *A
A = 0x44
D = D-A
A = RHS_D
D;JEQ
# Check for M.
A = char
D = *A
A = 0x4D
D = D-A
A = RHS_M
D;JEQ
# Check for 1.
A = char
D = *A
A = 0x31
D = D-A
A = RHS_One
D;JEQ
# None of the above branches worked, so we're looking at something we don't
# understand and should abort the program.
A = Error
JMP

# D operand means we need to set the swap bit (and the first operand should
# have been 0, A, or M, but we don't check that here. An appropriate check
# would be that either sw or zx is already set.)
  RHS_D:
A = 0x0040
D = A
A = LHS_SetBits
JMP

# Operand is M, set the mr bit.
  RHS_M:
A = 0x1000
D = A
A = LHS_SetBits
JMP

# Operand is 1, set op0 to turn add into inc and sub into dec.
# If the operator was not add or sub your machine code will be frogs.
  RHS_One:
A = 0x0100
D = A
# Fall through

# D contains some pile of bits. Set them in the opcode.
  RHS_SetBits:
A = opcode
*A = D | *A
# fall through

# Set next state to Jump and we're done here.
  RHS_Done:
A = Jump
D = A
A = state
*A = D
A = Mainloop
JMP

################################################################################
## Jump state                                                                 ##
################################################################################

# Handler for the jump flags. These go at the end of the instruction and consist
# of some combination of the <, =, and > characters, which directly set the lt,
# eq, and gt bits in the opcode.
# This has the same structure as the LHS/RHS states: check character, set bit
# in opcode. Unlike those states it doesn't proceed to a new state afterwards;
# the assembler sits in this state until the end of the line is reached.
  Jump:
# less than
A = char
D = *A
A = 0x3C
D = D-A
A = Jump_LT
D;JEQ
# equal
A = char
D = *A
A = 0x3D
D = D-A
A = Jump_EQ
D;JEQ
# greater than
A = char
D = *A
A = 0x3D
D = D-A
A = Jump_GT
D;JEQ
# None of the above branches worked, so we're looking at something we don't
# understand and should abort the program.
A = Error
JMP

  Jump_LT:
A = 0x0004
D = A
A = Jump_SetBits
JMP
  Jump_EQ:
A = 0x0002
D = A
A = Jump_SetBits
JMP
  Jump_GT:
A = 0x0001
D = A
A = Jump_SetBits
JMP

# D contains some pile of bits. Set them in the opcode and remain in the same
# state.
  Jump_SetBits:
A = opcode
*A = D | *A
A = Mainloop
JMP

################################################################################
## End of program stuff                                                       ##
################################################################################

# Error state. Write a single zero byte to the output so that external tools can
# tell something went wrong, since the output will have an odd number of bytes
# in it.
# Someday we should have a way to reopen and thus erase the file.
  Error:
A = stdout_bytes
*A = 0
# fall through to Exit

  Exit:
# end of program