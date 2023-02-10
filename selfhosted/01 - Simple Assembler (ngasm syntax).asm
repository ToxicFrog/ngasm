;;;; Assembler, stage 1 ;;;;
;
; This is a 1:1 translation of the stage 0 assembler into the syntax that it
; understands, so it can self-assemble.
; It doesn't support labels, but since the assembler emits one instruction per
; line, we can compute offsets as the line number of the label - 1 (since ROM is
; 0-indexed and editor lines are 1-indexed).

;;;; Program Code ;;;;

; Globals
; Most recently read character
;DEFINE &char 0
; Opcode under construction
;DEFINE &opcode 1
; True if we are in read-and-discard-comment mode
;DEFINE &in_comment 2
; Pointer to current state
;DEFINE &state 3

;DEFINE &stdin_status 0x7FF0
;DEFINE &stdin 0x7FF1
;DEFINE &stdout_bytes 0x7FF9
;DEFINE &stdout 0x7FFA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main loop and helpers                                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Bootup. Runs at start and at the beginning of each line to initialize
; the various globals.
;  :NewInstruction
; Set opcode to 0x8000, which is a no-op (computes D&A and discards it).
; We do this by computing 0x4000+0x4000 since we can't express 0x8000 directly.
@ 40000 ;16384
D = 0+A
D = D+A
@ 1 ; &opcode
M = 0|D
; Clear the in_comment flag
@ 2 ; &in_comment
M = 0&D
; Set the current state to NewLine, the start-of-line state
@ 173 ; :LineStart
D = 0|A
@ 3 ; &state
M = 0|D
; Fall through to Mainloop.

; Core loop.
; This reads input byte by byte. Spaces and comments are discarded, newlines
; trigger opcode emission, everything else is passed to the current state.
;  :Mainloop
; Read input status word, if end of file, end program.
@ 77760 ; &stdin_status
D = 0|M
@ 1133 ; :Exit
= 0|D =
; Read next byte of input and stash it in char
@ 77761 ; &stdin
D = 0|M
@ 0 ; &char
M = 0|D
; If it's a newline, run the end-of-line routine.
@ 12
D = D - A
@ 152 ; :EndOfLine
= 0|D =
; If we're in a comment, skip this character
@ 2 ; &in_comment
D = 0|M
@ 65 ; :Mainloop
= 0|D <>
; Also skip spaces
@ 0 ; &char
D = 0|M
@ 40
D = D - A
@ 65 ; :Mainloop
= 0|D =
; If it's a start-of-comment character, run CommentStart to set the in_comment flag
@ 0 ; &char
D = 0|M
@ 73
D = D - A
@ 143 ; :CommentStart
= 0|D =
; At this point, it's not a newline, it's not a space, it's not the start or
; interior of a comment, so it should hopefully be part of an instruction.
; Call the current state to deal with it. It will jump back to MainLoop when done.
@ 3 ; &state
A = 0|M
= 0|D <=>

;; Helper procedures for Mainloop. ;;

; Called when it sees the start-of-comment character. Sets the in_comment flag
; and ignores the input otherwise.
;  :CommentStart
@ 2 ; &in_comment
M = 0+1
@ 65 ; :Mainloop
= 0|D <=>

; Called to output the opcode being generated, at the end of a line. Jumps to
; NewInstruction when done to reinitialize the globals.
;  :EndOfLine
@ 1 ; &opcode
D = 0|M
@ 77772 ; &stdout
M = 0|D
@ 40 ; :NewInstruction
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LineStart state                                                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The base state that we get reset to at the end of every line.
; It looks at the first character of the line and if it's an @, transitions to
; LoadImmediate.
; Anything else causes a transition to Destination, to read the A/D/M bits at
; the start of a compute instruction.
;  :LineStart
; If it's not an @, we're looking at a compute instruction
@ 0 ; &char
D = 0|M
@ 100 ; '@'
D = D-A
@ 221 ; :LineStart_ComputeInstruction
= 0|D <>
; If we get here it's an @, so a load immediate -- clear the high bit in the
; opcode and set LoadImmediate as the state to process the rest of the line.
@ 1 ; &opcode
M = 0&A
@ 240 ; :LoadImmediate
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

; It's the start of a compute instruction. The first character is already going
; to be significant, so we need to set the current state to Destination and then
; jump to Destination rather than Mainloop, so we don't skip the current char.
;  :LineStart_ComputeInstruction:
@ 273 ; :Destination
D = 0|A
@ 3 ; &state
M = 0|D
@ 273 ; :Destination
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LoadImmediate state                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The state for reading the number in a load immediate instruction.
; The number is octal, so for each digit, we multiply the existing number by
; 8 (by repeated doubling via self-adding) and then add the new digit to it.
;  :LoadImmediate
; Start by making room in the opcode
@ 1 ; &opcode
D = 0|M
M = D+M
D = 0|M
M = D+M
D = 0|M
M = D+M
; Opcode has now been multiplied by 8, add the next digit.
@ 0 ; &char
D = 0|M
; Subtract '0' to get a value in the range 0-7
; or out of the range if the user typed in some sort of garbage, oh well
@ 60 ; '0'
D = D-A
@ 1 ; &opcode
M = D+M
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Destination state                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for reading the optional A, D, and M at the start of an instruction,
; designating the destination(s) for the computed values.
;  :Destination
; Check for =, which sends us to the next state (LHS)
@ 0 ; &char
D = 0|M
@ 75 ; '='
D = D-A
@ 336 ; :Destination_Finished
= 0|D =
; Check for A.
@ 0 ; &char
D = 0|M
@ 101 ; 'A'
D = D-A
@ 351 ; :Destination_A
= 0|D =
; Check for D.
@ 0 ; &char
D = 0|M
@ 104 ; 'D'
D = D-A
@ 356 ; :Destination_D
= 0|D =
; Check for M.
@ 0 ; &char
D = 0|M
@ 115 ; 'M'
D = D-A
@ 363 ; :Destination_M
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ 1126 ; :Error
= 0|D <=>

; We read an =, so set up the state transition.
;  :Destination_Finished
@ 411 ; :LHS
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

; The next three short procedures all set up D with the correct bit to set in
; the instruction and then jump to Destination_SetBits, which does the actual
; modification of the opcode.
;  :Destination_A
@ 40 ; 0x0020
D = 0|A
@ 370 ; :Destination_SetBits
= 0|D <=>
;  :Destination_D
@ 20 ; 0x0010
D = 0|A
@ 370 ; :Destination_SetBits
= 0|D <=>
;  :Destination_M
@ 10 ; 0x0008
D = 0|A
; fall through
; The bit we want is in D, so bitwise-or it into the opcode
;  :Destination_SetBits
@ 1 ; &opcode
M = D | M
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LHS operand state                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for reading the left-hand side of the ALU expression.
; This is a one-character state, so it processes whatever's in char and then
; immediately transitions to the Operator state.
; The LHS defaults to D, which requires no action. A or M require setting the
; sw bit; M additionally requires setting the mr bit. 0 requires setting the zx
; bit; it may also require setting sw or mr depending on what the RHS is, but
; that will be handled by the RHS state.
;  :LHS
; Check for A.
@ 0 ; &char
D = 0|M
@ 101 ; 'A'
D = D-A
@ 471 ; :LHS_A
= 0|D =
; Check for D.
@ 0 ; &char
D = 0|M
@ 104 ; 'D'
D = D-A
@ 504 ; :LHS_Done
= 0|D =
; Check for M.
@ 0 ; &char
D = 0|M
@ 115 ; 'M'
D = D-A
@ 463 ; :LHS_M
= 0|D =
; Check for 0.
@ 0 ; &char
D = 0|M
@ 60 ; '0'
D = D-A
@ 454 ; :LHS_Z
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ 1126 ; :Error
= 0|D <=>

; Operand is 0, set the zx bit.
;  :LHS_Z
@ 200 ; 0x0080
D = 0|A
@ 500 ; :LHS_SetBits
= 0|D <=>

; Operand is M, set the mr bit and fall through the LHS_A to set the sw bit.
;  :LHS_M
@ 10000 ; 0x1000
D = 0|A
; fall through to LHS_A.

; Operand is A, set the sw bit.
;  :LHS_A
@ 100 ; 0x1000
; Use | here so that the fallthrough case from LHS_M works as expected.
; If we came from LHS proper, D is guaranteed to be zero because we JEQ'd.
D = D|A

; D contains some pile of bits. Set them in the opcode.
;  :LHS_SetBits
@ 1 ; &opcode
M = D | M
; fall through
;  :LHS_Done
@ 531 ; :Operator
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Operator state                                                             ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for reading the ALU operator.
; It understands the following binary operations, with the following bit patterns:
;  +    add   0400
;  -    sub   0600
;  &    and   0000
;  |    or    0100
;  ^    xor   0200
;  !    not   0300
; inc and dec are handled in the RHS state.
;  :Operator
; add
@ 0 ; &char
D = 0|M
@ 53 ; '+'
D = D-A
@ 614 ; :Operator_Add
= 0|D =
; sub
@ 0 ; &char
D = 0|M
@ 55 ; '-'
D = D-A
@ 621 ; :Operator_Sub
= 0|D =
; and
@ 0 ; &char
D = 0|M
@ 46 ; &
D = D-A
@ 626 ; :Operator_And
= 0|D =
; or
@ 0 ; &char
D = 0|M
@ 174 ; '|'
D = D-A
@ 632 ; :Operator_Or
= 0|D =
; xor
@ 0 ; &char
D = 0|M
@ 136 ; '^'
D = D-A
@ 637 ; :Operator_Xor
= 0|D =
; not
@ 0 ; &char
D = 0|M
@ 41 ; '!'
D = D-A
@ 647 ; :Operator_Not
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ 1126 ; :Error
= 0|D <=>

; Helpers for the various ALU operations. Same deal as LHS here, they
; set the bits needed in D and then jump to SetBits to actually move
; them into the opcode.
;  :Operator_Add
@ 2000 ; 0x0400
D = 0|A
@ 664 ; :Operator_SetBits
= 0|D <=>
;  :Operator_Sub
@ 3000 ; 0x0600
D = 0|A
@ 664 ; :Operator_SetBits
= 0|D <=>
;  :Operator_And
D = 0&A
@ 664 ; :Operator_SetBits
= 0|D <=>
;  :Operator_Or
@ 400 ; 0x0100
D = 0|A
@ 664 ; :Operator_SetBits
= 0|D <=>
;  :Operator_Xor
@ 1000 ; 0x0200
D = 0|A
@ 664 ; :Operator_SetBits
= 0|D <=>

; This gets special handling because we need to skip the second operand
; entirely, since not is a unary operation.
;  :Operator_Not
@ 1400 ; 0x0300
D = 0|A
@ 1 ; &opcode
M = D | M
@ 1033 ; :Jump
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

; Write bits to opcode, set next state to RHS, return to main loop.
;  :Operator_SetBits
@ 1 ; &opcode
M = D | M
@ 711 ; :RHS
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; RHS operand state                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for the right-hand operand. This is basically the same as the
; state for the left-hand, except it understands 1 (as meaning "set the
; op0 bit to turn add/sub into inc/dec") rather than 0, and of course the
; bit patterns it emits are different.
; Note that there is no consistency checking with what LHS ingested, so
; you can ask it for invalid operations like "D&1" and it will generate
; something that isn't what you asked for -- in the above case D|A.
;  :RHS
; Check for A. This is the default case, so we set no bits.
@ 0 ; &char
D = 0|M
@ 101 ; 'A'
D = D-A
@ 1011 ; :RHS_Done
= 0|D =
; Check for D.
@ 0 ; &char
D = 0|M
@ 104 ; 'D'
D = D-A
@ 756 ; :RHS_D
= 0|D =
; Check for M.
@ 0 ; &char
D = 0|M
@ 115 ; 'M'
D = D-A
@ 765 ; :RHS_M
= 0|D =
; Check for 1.
@ 0 ; &char
D = 0|M
@ 61 ; '1'
D = D-A
@ 775 ; :RHS_One
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ 1126 ; :Error
= 0|D <=>

; D operand means we need to set the swap bit (and the first operand should
; have been 0, A, or M, but we don't check that here. An appropriate check
; would be that either sw or zx is already set.)
;  :RHS_D
@ 100 ; 0x0040
D = 0|A
@ 1003 ; :RHS_SetBits
= 0|D <=>

; Operand is M, set the mr bit.
;  :RHS_M
@ 10000 ; 0x1000
D = 0|A
@ 1003 ; :RHS_SetBits
= 0|D <=>

; Operand is 1, set op0 to turn add into inc and sub into dec.
; If the operator was not add or sub your machine code will be frogs.
;  :RHS_One
@ 400 ; 0x0100
D = 0|A
; Fall through

; D contains some pile of bits. Set them in the opcode.
;  :RHS_SetBits
@ 1 ; &opcode
M = D | M
; fall through

; Set next state to Jump and we're done here.
;  :RHS_Done
@ 1033 ; :Jump
D = 0|A
@ 3 ; &state
M = 0|D
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Jump state                                                                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Handler for the jump flags. These go at the end of the instruction and consist
; of some combination of the <, =, and > characters, which directly set the lt,
; eq, and gt bits in the opcode.
; This has the same structure as the LHS/RHS states: check character, set bit
; in opcode. Unlike those states it doesn't proceed to a new state afterwards;
; the assembler sits in this state until the end of the line is reached.
;  :Jump
; less than
@ 0 ; &char
D = 0|M
@ 74 ; '<'
D = D-A
@ 1066 ; :Jump_LT
= 0|D =
; equal
@ 0 ; &char
D = 0|M
@ 75 ; '='
D = D-A
@ 1073 ; :Jump_EQ
= 0|D =
; greater than
@ 0 ; &char
D = 0|M
@ 76 ; '>'
D = D-A
@ 1100 ; :Jump_GT
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ 1126 ; :Error
= 0|D <=>

;  :Jump_LT
@ 4 ; 0x0004
D = 0|A
@ 1110 ; :Jump_SetBits
= 0|D <=>
;  :Jump_EQ
@ 2 ; 0x0002
D = 0|A
@ 1110 ; :Jump_SetBits
= 0|D <=>
;  :Jump_GT
@ 1 ; 0x0001
D = 0|A
@ 1110 ; :Jump_SetBits
= 0|D <=>

; D contains some pile of bits. Set them in the opcode and remain in the same
; state.
;  :Jump_SetBits
@ 1 ; &opcode
M = D | M
@ 65 ; :Mainloop
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of program stuff                                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Error state. Write a single zero byte to the output so that external tools can
; tell something went wrong, since the output will have an odd number of bytes
; in it.
; Someday we should have a way to reopen and thus erase the file.
;  :Error
@ 77771 ; &stdout_bytes
M = 0&A
; fall through to Exit

;  :Exit
; end of program