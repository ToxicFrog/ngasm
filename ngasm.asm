;;;; Assembler, stage 3 ;;;;
;
; This refactors the assembler to make use of the labels feature added in stage
; 2. No functionality is changed but it should be easier to follow now.

; Globals
; Since each line outputs an instruction, we can use labels for our variables
; as well. In the future we'll have define but this works in the meantime.
; The convention used here is:
; - variable addresses start with :&
; - constants that are not memory addresses with :#
; - jump labels with plain :

; Most recently read character
:&char.
; Opcode under construction
:&opcode.
; True if we are in read-and-discard-comment mode
:&in_comment.
; Pointer to current state
:&state.

; Whether we're on the first pass (0) or the second pass (1).
; There are more elegant ways to do this but I can implement those once we have
; label support working. :)
:&pass.

; Program counter. Used to generate labels.
:&pc.

; Hash of current label. Filled in by states that read labels in the source code
; and used by routines that commit or look up labels.
:&label.

; Pointer just past the end of the symbol table. To write a new symbol we put
; it here and then increment this pointer. When resolving a symbol, if we reach
; this point, we've gone too far.
:&last_sym.
; Pointer to the current symbol we are looking at. Used during symbol resolution
; as scratch space.
:&this_sym.

; The actual table. The table is an array of [symbol_hash, value] pairs
; occupying two words each and stored contiguously in memory.
; This goes last since it will grow as new symbols are added and we don't want
; it overwriting something else!
:&symbols.

; Memory-mapped IO we still need to hard-code until we have define, using labels
; as variables only works for stuff where we don't care exactly where it ends up.
;DEFINE &stdin_status 0x7FF0
;DEFINE &stdin 0x7FF1
;DEFINE &stdout_bytes 0x7FF9
;DEFINE &stdout 0x7FFA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Initialization                                                             ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This needs to run once at program startup.
; It sets last_sym to point to the start of the symbol table so that we
; write symbols to the right place.
  :Init.
@ :&symbols.
D = 0|A
@ :&last_sym.
M = 0|D
; Fall through to :NewInstruction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main loop and helpers                                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is called once at startup and once at the beginning of each line.
; It has been relocated here from the start of the file so we can put Init
; in front of it.
  :NewInstruction.
; Set opcode to 0x8000, which is a no-op (computes D&A and discards it).
; We do this by computing 0x4000+0x4000 since we can't express 0x8000 directly.
@ 40000 ;16384
D = 0+A
D = D+A
@ :&opcode.
M = 0|D
; Clear the in_comment flag
@ :&in_comment.
M = 0&D
; Set the current state to NewLine, the start-of-line state
@ :LineStart.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
= 0|D <=>

; Core loop.
; This reads input byte by byte. Spaces and comments are discarded, newlines
; trigger opcode emission, everything else is passed to the current state.
  :MainLoop.
; Read input status word, if end of file, start next pass or end program.
@ 77760 ; &stdin_status
D = 0|M
@ :NextPass.
= 0|D =
; Read next byte of input and stash it in char
@ 77761 ; &stdin
D = 0|M
@ :&char.
M = 0|D
; If it's a newline, run the end-of-line routine.
@ 12
D = D - A
@ :EndOfLine.
= 0|D =
; If we're in a comment, skip this character
@ :&in_comment.
D = 0|M
@ :MainLoop.
= 0|D <>
; Also skip spaces
@ :&char.
D = 0|M
@ 40
D = D - A
@ :MainLoop.
= 0|D =
; If it's a start-of-comment character, run CommentStart to set the in_comment flag
@ :&char.
D = 0|M
@ 73
D = D - A
@ :CommentStart.
= 0|D =
; At this point, it's not a newline, it's not a space, it's not the start or
; interior of a comment, so it should hopefully be part of an instruction.
; Call the current state to deal with it. It will jump back to MainLoop when done.
@ :&state.
A = 0|M
= 0|D <=>

;; Helper procedures for MainLoop. ;;

; Called when it sees the start-of-comment character. Sets the in_comment flag
; and ignores the input otherwise.
  :CommentStart.
@ :&in_comment.
M = 0+1
@ :MainLoop.
= 0|D <=>

; Called at end-of-file. At the end of the first pass this needs to rewind the
; file and start the second pass; at the end of the second pass it exits.
  :NextPass.
; If pass>0, exit the program.
@ :&pass.
D = 0|M
@ :Exit.
= 0|D >
; Otherwise, rewind stdin to start of file by writing a 0 to it
@ 77760 ; &stdin_status
M = 0&D
; Then increment pass and restart the main loop.
@ :&pass.
M = M+1
@ :MainLoop.
= 0|D <=>


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End-of-line handling                                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called at the end of every line. Checks pass to determine what it should do.
; In pass 0, it increments pc so that we know what addresses to associate with
; labels when we encounter them; in pass 1 it actually emits code.
; In either case it calls NewInstruction afterwards to reset the parser state,
; opcode buffer, etc.
  :EndOfLine.
; If pass == 0, call _FirstPass, else _SecondPass.
@ :&pass.
D = 0|M
@ :EndOfLine_FirstPass.
= 0|D =
@ :EndOfLine_SecondPass.
= 0|D <=>

  :EndOfLine_FirstPass.
; First pass, so increment PC and output nothing.
@ :&pc.
M = M+1
@ :NewInstruction.
= 0|D <=>

  :EndOfLine_SecondPass.
; Second pass, so write the opcode to stdout. On lines containing no code,
; NewInstruction will have set this up as a no-op, so it's safe to emit
; regardless.
@ :&opcode.
D = 0|M
@ 77772 ; &stdout
M = 0|D
@ :NewInstruction.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LineStart state                                                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This state sees the first (non-whitespace, non-comment) character on each line.
; Its job is to decide, based on that character, what sort of line this is:
;   @ means that it's a load immediate instruction
;   : means that it's a label definition
;   anything else means a compute instruction
; Label definitions have special handling based on the pass. If we're in pass 0,
; it transfers control to ReadLabel for the rest of the line, which will read in
; the label and add a symbol table entry for it based on PC.
; In pass 1, however, it instead calls CommentStart, treating labels like
; comments. (Actual uses of labels once defined are always as part of an @
; load immediate instruction, so those are handled in LoadImmediate.)
  :LineStart.
; Is it an @? If so this is a load immediate A opcode.
@ :&char.
D = 0|M
@ 100 ; '@'
D = D-A
@ :LineStart_LoadImmediate.
= 0|D =
; If it's a :, this is a label definition and we branch further depending on
; what pass we're on.
@ :&char.
D = 0|M
@ 72 ; ':'
D = D-A
@ :LineStart_Label.
= 0|D =
; None of the above match.
; It's the start of a compute instruction. The first character is already going
; to be significant, so we need to set the current state to Destination and then
; jump to Destination rather than MainLoop, so we don't skip the current char.
@ :Destination.
D = 0|A
@ :&state.
M = 0|D
@ :Destination.
= 0|D <=>

; Called when the line starts with @. Set the current state to LoadImmediate
; and return control to the main loop.
  :LineStart_LoadImmediate.
@ :LoadImmediate.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
= 0|D <=>

; Called when the line starts with :, denoting a label definition.
; If in the first pass, we transfer control to ReadLabel
; else treat it like a comment.
  :LineStart_Label.
@ :&pass.
D = 0|M
; On pass 1, call CommentStart, the same routine used by the main loop when it
; sees a ';' character. This will flag this character, and the rest of the line,
; as a comment.
@ :CommentStart.
= 0|D <>
; On pass 0, we need to actually read in the label and associate a value with it.
; ReadLabel_Init will initialize the label reader, read in the label, and,
; knowing that we're on the first pass, create a new symbol table entry for it.
@ :ReadLabel_Init.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LoadImmediate state                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is called immediately after LineStart sees an @. If it sees a :, it passes
; control to LoadImmediate_Label to read the label. Otherwise it passes control
; to LoadImmediate_Constant to read an octal number.
  :LoadImmediate.
@ :&char.
D = 0|M
@ 72 ; ':'
D = D-A
@ :LoadImmediate_Label.
= 0|D =
; No label? Transfer control to LoadImmediate_Constant instead, and call it immediately to process the first digit.
@ :LoadImmediate_Constant.
D = 0|A
@ :&state.
M = 0|D
@ :LoadImmediate_Constant.
= 0|D <=>

; This becomes the active state after LoadImmediate sees a :. It is responsible
; for processing the label character by character into &label.
  :LoadImmediate_Label.
; First set ourself as the current state, so that it doesn't go through
; LoadImmediate above when it sees the next character and end up flopping
; between label and constant mode.
@ :LoadImmediate_Label.
D = 0|A
@ :&state.
M = 0+D
; If we're on the first pass, we aren't guaranteed to have bindings for these
; symbols yet, but we also aren't generating code yet, so just ignore every
; character we're passed and jump back to MainLoop.
@ :&pass.
D = 0|M
@ :MainLoop.
= 0|D =
; We're on pass 1. We need to actually resolve the symbol.
; ReadLabel_Init will initialize the label reader and set it as the current
; state. When it's done reading the label it will (knowing that it's on pass 1)
; leave the associated value in the opcode buffer, and EndOfLine will handle
; outputting it.
@ :ReadLabel_Init.
= 0|D <=>

; The state for reading the number in a load immediate instruction.
; The number is octal, so for each digit, we multiply the existing number by
; 8 (by repeated doubling via self-adding) and then add the new digit to it.
  :LoadImmediate_Constant.
; Start by making room in the opcode
@ :&opcode.
D = 0|M
M = D+M
D = 0|M
M = D+M
D = 0|M
M = D+M
; Opcode has now been multiplied by 8, add the next digit.
@ :&char.
D = 0|M
; Subtract '0' to get a value in the range 0-7
; or out of the range if the user typed in some sort of garbage, oh well
@ 60 ; '0'
D = D-A
@ :&opcode.
M = D+M
@ :MainLoop.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Destination state                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for reading the optional A, D, and M at the start of an instruction,
; designating the destination(s) for the computed values.
  :Destination.
; Check for =, which sends us to the next state (LHS)
@ :&char.
D = 0|M
@ 75 ; '='
D = D-A
@ :Destination_Finished.
= 0|D =
; Check for A.
@ :&char.
D = 0|M
@ 101 ; 'A'
D = D-A
@ :Destination_A.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 104 ; 'D'
D = D-A
@ :Destination_D.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 115 ; 'M'
D = D-A
@ :Destination_M.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

; We read an =, so set up the state transition.
  :Destination_Finished.
@ :LHS.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
= 0|D <=>

; The next three short procedures all set up D with the correct bit to set in
; the instruction and then jump to Destination_SetBits, which does the actual
; modification of the opcode.
  :Destination_A.
@ 40 ; 0x0020
D = 0|A
@ :Destination_SetBits.
= 0|D <=>
  :Destination_D.
@ 20 ; 0x0010
D = 0|A
@ :Destination_SetBits.
= 0|D <=>
  :Destination_M.
@ 10 ; 0x0008
D = 0|A
; fall through
; The bit we want is in D, so bitwise-or it into the opcode
  :Destination_SetBits.
@ :&opcode.
M = D | M
@ :MainLoop.
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
  :LHS.
; Check for A.
@ :&char.
D = 0|M
@ 101 ; 'A'
D = D-A
@ :LHS_A.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 104 ; 'D'
D = D-A
@ :LHS_Done.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 115 ; 'M'
D = D-A
@ :LHS_M.
= 0|D =
; Check for 0.
@ :&char.
D = 0|M
@ 60 ; '0'
D = D-A
@ :LHS_Z.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

; Operand is 0, set the zx bit.
  :LHS_Z.
@ 200 ; 0x0080
D = 0|A
@ :LHS_SetBits.
= 0|D <=>

; Operand is M, set the mr bit and fall through the LHS_A to set the sw bit.
  :LHS_M.
@ 10000 ; 0x1000
D = 0|A
; fall through to LHS_A.

; Operand is A, set the sw bit.
  :LHS_A.
@ 100 ; 0x1000
; Use | here so that the fallthrough case from LHS_M works as expected.
; If we came from LHS proper, D is guaranteed to be zero because we JEQ'd.
D = D|A

; D contains some pile of bits. Set them in the opcode.
  :LHS_SetBits.
@ :&opcode.
M = D | M
; fall through
  :LHS_Done.
@ :Operator.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
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
  :Operator.
; add
@ :&char.
D = 0|M
@ 53 ; '+'
D = D-A
@ :Operator_Add.
= 0|D =
; sub
@ :&char.
D = 0|M
@ 55 ; '-'
D = D-A
@ :Operator_Sub.
= 0|D =
; and
@ :&char.
D = 0|M
@ 46 ; &
D = D-A
@ :Operator_And.
= 0|D =
; or
@ :&char.
D = 0|M
@ 174 ; '|'
D = D-A
@ :Operator_Or.
= 0|D =
; xor
@ :&char.
D = 0|M
@ 136 ; '^'
D = D-A
@ :Operator_Xor.
= 0|D =
; not
@ :&char.
D = 0|M
@ 41 ; '!'
D = D-A
@ :Operator_Not.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

; Helpers for the various ALU operations. Same deal as LHS here, they
; set the bits needed in D and then jump to SetBits to actually move
; them into the opcode.
  :Operator_Add.
@ 2000 ; 0x0400
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Sub.
@ 3000 ; 0x0600
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_And.
D = 0&A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Or.
@ 400 ; 0x0100
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Xor.
@ 1000 ; 0x0200
D = 0|A
@ :Operator_SetBits.
= 0|D <=>

; This gets special handling because we need to skip the second operand
; entirely, since not is a unary operation.
  :Operator_Not.
@ 1400 ; 0x0300
D = 0|A
@ :&opcode.
M = D | M
@ :Jump.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
= 0|D <=>

; Write bits to opcode, set next state to RHS, return to main loop.
  :Operator_SetBits.
@ :&opcode.
M = D | M
@ :RHS.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
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
  :RHS.
; Check for A. This is the default case, so we set no bits.
@ :&char.
D = 0|M
@ 101 ; 'A'
D = D-A
@ :RHS_Done.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 104 ; 'D'
D = D-A
@ :RHS_D.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 115 ; 'M'
D = D-A
@ :RHS_M.
= 0|D =
; Check for 1.
@ :&char.
D = 0|M
@ 61 ; '1'
D = D-A
@ :RHS_One.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

; D operand means we need to set the swap bit (and the first operand should
; have been 0, A, or M, but we don't check that here. An appropriate check
; would be that either sw or zx is already set.)
  :RHS_D.
@ 100 ; 0x0040
D = 0|A
@ :RHS_SetBits.
= 0|D <=>

; Operand is M, set the mr bit.
  :RHS_M.
@ 10000 ; 0x1000
D = 0|A
@ :RHS_SetBits.
= 0|D <=>

; Operand is 1, set op0 to turn add into inc and sub into dec.
; If the operator was not add or sub your machine code will be frogs.
  :RHS_One.
@ 400 ; 0x0100
D = 0|A
; Fall through

; D contains some pile of bits. Set them in the opcode.
  :RHS_SetBits.
@ :&opcode.
M = D | M
; fall through

; Set next state to Jump and we're done here.
  :RHS_Done.
@ :Jump.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
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
  :Jump.
; less than
@ :&char.
D = 0|M
@ 74 ; '<'
D = D-A
@ :Jump_LT.
= 0|D =
; equal
@ :&char.
D = 0|M
@ 75 ; '='
D = D-A
@ :Jump_EQ.
= 0|D =
; greater than
@ :&char.
D = 0|M
@ 76 ; '>'
D = D-A
@ :Jump_GT.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

  :Jump_LT.
@ 4 ; 0x0004
D = 0|A
@ :Jump_SetBits.
= 0|D <=>
  :Jump_EQ.
@ 2 ; 0x0002
D = 0|A
@ :Jump_SetBits.
= 0|D <=>
  :Jump_GT.
@ 1 ; 0x0001
D = 0|A
@ :Jump_SetBits.
= 0|D <=>

; D contains some pile of bits. Set them in the opcode and remain in the same
; state.
  :Jump_SetBits.
@ :&opcode.
M = D | M
@ :MainLoop.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of program stuff                                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Error state. Write a single zero byte to the output so that external tools can
; tell something went wrong, since the output will have an odd number of bytes
; in it.l
; Someday we should have a way to reopen and thus erase the file.
  :Error.
@ 77771 ; &stdout_bytes
M = 0&A
; fall through to Exit

  :Exit.
; Jump off the end of ROM
@ 77777
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Label support                                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; To support labels we need a number of new features:
; - understanding ":foo." as defining a label foo at the address at which it occurs
; - understanding "@ :foo." as loading A with the value recorded for the label foo
; - remembering, and being able to look up, the value associated with each label
; once we have these capabilities, we'll be able to re-use them to implement
; defines, too.
;
; Labels may be referenced before they are defined, so in order to support them
; properly we need to process the input file twice. In the first pass:
; - at end of line, increment the program counter but output nothing;
; - upon seeing a label definition, record the current value of PC in the symbol
;   table as the value of that label;
; - upon seeing a label reference, pretend it's 0.
; And then, in the second pass:
; - at end of line, output the current instruction;
; - upon seeing a label definition, ignore it;
; - upon seeing a label reference, look it up in the symbol table.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Label reading                                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is a preamble to ReadLabel (below). It sets the state pointer to
; ReadLabel so future inputs will be directed to it, and clears the label
; variable so we can start reading into it.
; When LineStart or LoadImmediate encounter a label, this is what they call.
  :ReadLabel_Init.
@ :&label.
M = 0&D
@ :ReadLabel.
D = 0|A
@ :&state.
M = 0|D
; fall through to ReadLabel

; This state is entered when the program encounters a label in a location where
; one is expected, i.e. a label definition or LoadImmediate. It is responsible
; for reading the label into the label variable. Upon finishing the read, it
; either writes it to the symbol table (first pass) or replaces it with the
; value bound to it and calls LoadImmediate_ResolveSymbol (second pass).
  :ReadLabel.
@ :&char.
D = 0|M
@ 56 ; '.'
D = D-A
@ :ReadLabel_Done.
= 0|D =
; Not at end, so add the just-read character to the label hash. Any non-whitespace
; non-. character is valid.
; First, double the existing hash to shift left 1 bit.
@ :&label.
D = 0|M
D = D+M
; Then add the new character to it.
@ :&char.
D = D+M
@ :&label.
M = 0|D
; return to main loop
@ :MainLoop.
= 0|D <=>

; This is called when ReadLabel reads the terminating '.'. It looks at pass to
; determine whether to call ReadLabel_Bind or ReadLabel_Resolve.
  :ReadLabel_Done.
@ :&pass.
D = 0|M
; pass=0? we're still building the symbol table, call bind.
@ :ReadLabel_Bind.
= 0|D =
; else call resolve
@ :ReadLabel_Resolve.
= 0|D <=>

; This is called to bind a new entry in the symbol table to the current program
; counter value.
  :ReadLabel_Bind.
; First, write the current value of label to *last_sym
@ :&label.
D = 0|M
@ :&last_sym.
A = 0|M
M = 0|D
; increment last_sym so it points to the value slot
@ :&last_sym.
M = M+1
; Write PC to that slot
@ :&pc.
D = 0|M
@ :&last_sym.
A = 0|M
M = 0|D
; increment last_sym again
@ :&last_sym.
M = M+1
; done binding, return to main loop
@ :MainLoop.
= 0|D <=>

; This is called when resolving a symbol.
; It is reached when the program sees a @ (load immediate) followed by a label.
; At this point, ReadLabel proper is done and the label hash is stored in label.
; We need to scan the symbol table for the label and overwrite the opcode global
; with the associated value; it will then be output at the end of the line.
  :ReadLabel_Resolve.
; Startup code - set this_sym = &symbols
@ :&symbols.
D = 0|A
@ :&this_sym.
M = 0|D
  :ReadLabel_Resolve_Loop.
; Are we at the end of the symbol table? If so, error out.
@ :&last_sym.
D = 0|M
@ :&this_sym.
D = D-M
@ :Error.
= 0|D =
; Check if the current symbol is the one we're looking for.
@ :&this_sym.
A = 0|M ; fixed?
D = 0|M
@ :&label.
D = D-M
@ :ReadLabel_Resolve_Success.
= 0|D =
; It wasn't :( Advance this_sym by two to point to the next entry, and loop.
@ :&this_sym.
M = M+1
M = M+1
@ :ReadLabel_Resolve_Loop.
= 0|D <=>

; Called when we successfully find an entry in the symbol table. this_sym holds
; a pointer to the label cell of the entry, so we need to inc it to get the
; value cell.
  :ReadLabel_Resolve_Success.
@ :&this_sym.
A = M+1
D = 0|M
; now write the value into the opcode global
@ :&opcode.
M = 0|D
; At the moment this routine is only called when resolving a label as part of a
; LoadImmediate instruction, so that's all we need to do.
; As one final check, set the current state to Error -- if there is any more
; code on this line after the label, that is VERBOTEN and we will properly
; abort the run.
@ :Error.
D = 0|A
@ :&state.
M = 0|D
@ :MainLoop.
= 0|D <=>
