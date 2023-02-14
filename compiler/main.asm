;;;; Assembler, stage 4 ;;;;
;
; This adds a number of new features:
; - character constants
; - decimal and hexadecimal constants (octal constants are removed)
; ? constant definitions
; ? labels no longer required to end with .
; ? macros?

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

; Called at the end of every line.
; First, calls the current state with char=\0 to tell it that we've reached EOL;
; states which cannot appear at EOL will react by calling Error, other states
; should do whatever cleanup they need to do and then call EndOfLine_Continue.
  :EndOfLine.
@ :&char.
M = 0&D
@ :&state.
A = 0|M
= 0|D <=>

; Called after state cleanup, and checks pass to know what to do.
; In pass 0, it increments pc so that we know what addresses to associate with
; labels when we encounter them; in pass 1 it actually emits code.
; In either case it calls NewInstruction afterwards to reset the parser state,
; opcode buffer, etc.
  :EndOfLine_Continue.
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
;   & or # means that it's a constant definition
;   anything else means a compute instruction
; Label definitions have special handling based on the pass. If we're in pass 0,
; it transfers control to ReadLabel for the rest of the line, which will read in
; the label and add a symbol table entry for it based on PC.
; In pass 1, however, it instead calls CommentStart, treating labels like
; comments. (Actual uses of labels once defined are always as part of an @
; load immediate instruction, so those are handled in LoadImmediate.)
  :LineStart.
; Check if we're at end of line, if so just do nothing
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
= 0|D =
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
; If it's a &, this is a constant definition - we need to read the label, then
; the value.
@ :&char.
D = 0|M
@ 46 ; '&'
D = D-A
@ :LineStart_Constant.
= 0|D =
; Same deal with # as with &.
@ :&char.
D = 0|M
@ 43 ; '#'
D = D-A
@ :LineStart_Constant.
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
; Sym_Read will take over the state machine until it's done reading in the
; label, then call sym_next, which we will point at BindPC to associate the
; label with the current program counter.
@ :BindPC.
D = 0|M
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

; Called when the line starts with & or #, denoting a constant definition.
  :LineStart_Constant.

; Called when we have successfully read in a label definition. This should in
; practice be called at end of line via Sym_Read, so char=\0 and EndOfLine_Continue
; is waiting for us.
; So, we need to:
; - set sym_next to EndOfLine_Continue, so Sym_Bind jumps straight there
;   once we're done
; - copy PC into sym_value and then call Sym_Bind.
  :BindPC.
; set up sym_next
@ :EndOfLine_Continue.
D = 0|A
@ :&sym_next.
M = 0|D
; set up PC
@ :&pc.
D = 0|M
@ :&sym_value.
M = 0|D
@ :Sym_Bind.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LoadImmediate state                                                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is called immediately after LineStart sees an @. It dispatches on the
; first character it sees; a :, &, or # means a symbol reference which must be
; resolved using the symbol table, a ' means a character constant, a $ means a
; hexadecimal constant, and anything else means a decimal constant.
  :LoadImmediate.
; First, check for ':', '&', and '#'. These all use LoadImmediate_Symbol to
; resolve a symbol into a value.
@ :&char.
D = 0|M
@ 72 ; ':'
D = D-A
@ :LoadImmediate_Symbol.
= 0|D =
@ :&char.
D = 0|M
@ 43 ; '#'
D = D-A
@ :LoadImmediate_Symbol.
= 0|D =
@ :&char.
D = 0|M
@ 46 ; '&'
D = D-A
@ :LoadImmediate_Symbol.
= 0|D =
; Now check for a character constant.
@ :&char.
D = 0|M
@ 47 ; "'"
D = D-A
@ :LoadImmediate_Character.
= 0|D =
; Not a symbol or a character, so maybe it's a hex constant starting with $...
@ :&char.
D = 0|M
@ 44 ; '$'
D = D-A
@ :LoadImmediate_HexConstant.
= 0|D =
; None of the above? Assume it's a decimal constant
@ :LoadImmediate_DecConstant.
D = 0|A
@ :&state.
M = 0|D
@ :LoadImmediate_DecConstant.
= 0|D <=>

; This is called when LoadImmediate sees the start of a symbol reference.
; It uses Sym_Read to read in the symbol, then Sym_Resolve to get the actual
; value it needs to emit.
  :LoadImmediate_Symbol.
@ :LoadImmediate_Symbol_DoResolve.
D = 0|M
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

; Called immediately after the above. Performs resolution of the just-ingested
; symbol -- on the second pass. On the first pass it just ignores the result
; and jumps to EndOfLine_Continue (since this should only be called at EOL).
  :LoadImmediate_Symbol_DoResolve.
@ :&pass.
D = 0|M
@ :EndOfLine_Continue.
= 0|D =
@ :LoadImmediate_Symbol_ResolveDone.
D = 0|M
@ :&sym_next.
M = 0|D
@ :Sym_Resolve.
= 0|D <=>

; Called after symbol resolution completes. Writes the value of the resolved
; symbol into the opcode buffer.
  :LoadImmediate_Symbol_ResolveDone.
@ :&sym_value.
D = 0|M
@ :&opcode.
M = 0|D
; and since, again, this should only be called at EOL, we return control to
; the end of line handler.
@ :EndOfLine_Continue.
= 0|D <=>

; The state for reading a character constant. Character constants have the
; format 'x and scan as the character code for x, so (e.g.) 'a is 97.
  :LoadImmediate_Character.
; Set ourself as the current state first
@ :LoadImmediate_Character.
D = 0|A
@ :&state.
M = 0+D
; If char is 0 we're at EOL and have nothing further to do
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
= 0|D =
; Otherwise just copy char into opcode
@ :&char.
D = 0|M
@ :&opcode.
M = 0+D
@ :MainLoop.
= 0|D <=>

; Called by LoadImmediate on encountering the leading $ of a hex constant.
; Unlike DecimalConstant we don't want to ingest the first character of the
; constant (since $ is not a digit), so we just set ReadDigit as the current
; state and return to the main loop, which will start feeding it characters
; starting with the *next* character.
  :LoadImmediate_HexConstant.
@ :LoadImmediate_HexConstant_ReadDigit.
D = 0|A
@ :&state.
M = 0+D
@ :MainLoop.
= 0|D <=>

; The state for reading a hex constant. This is equivalent to a decimal constant
; except that (a) we multiply by 16 instead of by 10 each digit and (b) we understand
; the digits A-F and a-f as corresponding to the values 10-15.
  :LoadImmediate_HexConstant_ReadDigit.
; Check if we're at end of line, if so just do nothing
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
= 0|D =
; Start by making room in the opcode
@ :&opcode.
D = 0|M
; Add D to M 15 times for a total of x16
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
; Now we branch off depending on whether we have an a-f, A-F, or 0-9
; really simple checks here (no error catchment): if it's >= a we have a-f,
; otherwise if it's >= A we have A-F, otherwise it's 0-9.
@ :&char.
D = 0|M
@ 141 ; 'a'
D = D-A
@ :LoadImmediate_HexLowercase.
= 0|D >=
@ :&char.
D = 0|M
@ 101 ; 'A'
D = D-A
@ :LoadImmediate_HexUppercase.
= 0|D >=
@ :LoadImmediate_HexNumericDigit.
= 0|D <=>

  :LoadImmediate_HexLowercase.
@ :&char.
D = 0|M
@ 127 ; 'a' - 10
D = D-A
@ :&opcode.
M = D+M
@ :MainLoop.
= 0|D <=>

  :LoadImmediate_HexUppercase.
@ :&char.
D = 0|M
@ 67 ; 'A' - 10
D = D-A
@ :&opcode.
M = D+M
@ :MainLoop.
= 0|D <=>

  :LoadImmediate_HexNumericDigit.
@ :&char.
D = 0|M
@ 60 ; '0'
D = D-A
@ :&opcode.
M = D+M
@ :MainLoop.
= 0|D <=>

; The state for reading the number in a load immediate instruction.
; The number is decimal, so for each digit, we multiply the existing number by
; 10 by repeated addition, then add the new digit to it.
  :LoadImmediate_DecConstant.
; Check if we're at end of line, if so just do nothing
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
= 0|D =
; Start by making room in the opcode
@ :&opcode.
D = 0|M
; Add D to M 9 times for a total of x10
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
; Now add the next digit
@ :&char.
D = 0|M
; Subtract '0' to get a value in the range 0-9
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
; If char is \0 we're at end of line, no special cleanup needed so just continue
; EOL handling.
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
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
; If char is \0 we're at end of line, no special cleanup needed so just continue
; EOL handling.
@ :&char.
D = 0|M
@ :EndOfLine_Continue.
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
; in it.
; Someday we should have a way to reopen and thus erase the file.
  :Error.
@ 77771 ; &stdout_bytes
M = 0&A
; fall through to Exit

  :Exit.
; Jump off the end of ROM
@ 77777
= 0|D <=>

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
