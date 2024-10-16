;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Compiler variables                                                         ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Most recently read character
&core/char = $50
; Opcode under construction
&core/opcode = $51
; True if we are in read-and-discard-comment mode
&core/in-comment = $52
; Pointer to current state
&core/state = $53
; Number of current line. Used for error reporting.
&core/line-num = $54

; Whether we're on the first pass (0) or the second pass (1).
; There are more elegant ways to do this but I can implement those once we have
; label support working. :)
&core/pass = $55

; Program counter. Used to generate labels.
&core/pc = $56
; Offset in source file. Used to generate macros.
&core/fseek = $57

&stdin.status = $7FF0
&stdin.bytes = $7FF1
&stdout.bytes = $7FF9
&stdout.words = $7FFA

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Initialization                                                             ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This needs to run once at program startup.
; It sets last_sym to point to the start of the symbol table so that we
; write symbols to the right place.
  :Init
~stack/init,$4000
@ :&symbols.
D = 0|A
@ &sym/last
M = 0|D
@ &core/line-num  ; initialize line number to 1
M = 0+1
; initialize macroexpansion stack
@ &macros/stack
D = 0|A
@ &macros/sp
M = 0|D
; Fall through to :NewInstruction

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main loop and helpers                                                      ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is called once at startup and once at the beginning of each line.
; It has been relocated here from the start of the file so we can put Init
; in front of it.
  :NewInstruction
; Set opcode to 0x8000, which is a no-op (computes D&A and discards it).
; We do this by computing 0x4000+0x4000 since we can't express 0x8000 directly.
@ 040000 ;16384
D = 0+A
D = D+A
@ &core/opcode
M = 0|D
; Clear the in_comment flag
@ &core/in-comment
M = 0&D
; Set the current state to NewLine, the start-of-line state
@ :LineStart
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

; Core loop.
; This reads input byte by byte. Spaces and comments are discarded, newlines
; trigger opcode emission, everything else is passed to the current state.
  :MainLoop
; Read input status word, if end of file, start next pass or end program.
@ &stdin.status
D = 0|M
@ :NextPass
= 0|D =
; Read next byte of input and stash it in char
@ &stdin.bytes
D = 0|M
@ &core/char
M = 0|D
; Increment the fseek counter
@ &core/fseek
M = M+1
; If it's a newline, run the end-of-line routine.
@ &core/char
D = 0|M
@ 012
D = D - A
@ :EndOfLine
= 0|D =
; If we're in a comment, skip this character
@ &core/in-comment
D = 0|M
@ :MainLoop
= 0|D <>
; Also skip spaces
@ &core/char
D = 0|M
@ 040
D = D - A
@ :MainLoop
= 0|D =
; If it's a start-of-comment character, run CommentStart to set the in_comment flag
@ &core/char
D = 0|M
@ 073
D = D - A
@ :CommentStart
= 0|D =
; At this point, it's not a newline, it's not a space, it's not the start or
; interior of a comment, so it should hopefully be part of an instruction.
; Call the current state to deal with it. It will jump back to MainLoop when done.
@ &core/state
A = 0|M
= 0|D <=>

;; Helper procedures for MainLoop. ;;

; Called when it sees the start-of-comment character. Sets the in_comment flag
; and ignores the input otherwise.
  :CommentStart
@ &core/in-comment
M = 0+1
~jmp,:MainLoop

; Called at end-of-file. At the end of the first pass this needs to rewind the
; file and start the second pass; at the end of the second pass it exits.
  :NextPass
; If pass>0, exit the program.
@ &core/pass
D = 0|M
@ :Finalize
= 0|D >
; Otherwise, rewind stdin to start of file by writing a 0 to it
@ &stdin.status
M = 0&D
; Reset the program counter to 0
@ &core/pc
M = 0&D
; And the seek point
@ &core/fseek
M = 0&D
; Then increment pass, reset the line counter, and restart the main loop.
@ &core/pass
M = M+1
@ &core/line-num
M = 0+1
~jmp,:MainLoop


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End-of-line handling                                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called at the end of every line.
; First, calls the current state with char=\0 to tell it that we've reached EOL;
; states which cannot appear at EOL will react by calling Error, other states
; should do whatever cleanup they need to do and then call EndOfLine_Continue.
  :EndOfLine
; If we're in a macro, don't increment line number
@ &macros/in-expansion
D = 0|M
@ :EndOfLine_NoLineNum
= 0|D <>
@ &core/line-num
M = M+1
  :EndOfLine_NoLineNum
@ &core/char
M = 0&D
@ &core/state
A = 0|M
= 0|D <=>


; Called after state cleanup, and checks pass to know what to do.
; In pass 0, it increments pc so that we know what addresses to associate with
; labels when we encounter them; in pass 1 it actually emits code.
; In either case it calls NewInstruction afterwards to reset the parser state,
; opcode buffer, etc.
  :EndOfLine_Continue
; If pass == 0, call _FirstPass, else _SecondPass.
@ &core/pass
D = 0|M
@ :EndOfLine_FirstPass
= 0|D =
~jmp,:EndOfLine_SecondPass

  :EndOfLine_FirstPass
; First pass, so increment PC and output nothing.
@ &core/pc
M = M+1
~jmp,:NewInstruction

  :EndOfLine_SecondPass
; Second pass, so write the opcode to stdout. On lines containing no code,
; NewInstruction will have set this up as a no-op, so it's safe to emit
; regardless.
@ &core/opcode
D = 0|M
@ &stdout.words
M = 0|D
; Also increment PC, since relative jumps are calculated on the second pass.
@ &core/pc
M = M+1
~jmp,:NewInstruction

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
  :LineStart
; Check if we're at end of line, if so just do nothing
@ &core/char
D = 0|M
@ :EndOfLine_Continue
= 0|D =
; Is it an @? If so this is a load immediate A opcode.
@ &core/char
D = 0|M
@ 0100 ; '@'
D = D-A
@ :LineStart_LoadImmediate
= 0|D =
; If it's a :, this is a label definition and we branch further depending on
; what pass we're on.
@ &core/char
D = 0|M
@ 072 ; ':'
D = D-A
@ :LineStart_Label
= 0|D =
; If it's a &, this is a constant definition - we need to read the label, then
; the value.
@ &core/char
D = 0|M
@ 046 ; '&'
D = D-A
@ :LineStart_Constant
= 0|D =
; Same deal with # as with &.
@ &core/char
D = 0|M
@ 043 ; '#'
D = D-A
@ :LineStart_Constant
= 0|D =
; If it's a [, this is the start of a macro definition.
@ &core/char
D = 0|M
@ 0133 ; '['
D = D-A
@ :Macro_Begin
= 0|D =
; If it's a ], this is the end of a macro definition.
@ &core/char
D = 0|M
@ 0135 ; ']'
D = D-A
@ :Macro_End
= 0|D =
; If it's a ~, this is a macro invokation
@ &core/char
D = 0|M
@ 0176 ; '~'
D = D-A
@ :Macro_Expand
= 0|D =
; None of the above match.
; It's the start of a compute instruction. The first character is already going
; to be significant, so we need to set the current state to Destination and then
; jump to Destination rather than MainLoop, so we don't skip the current char.
@ :Destination
D = 0|A
@ &core/state
M = 0|D
~jmp,:Destination

; Called when the line starts with @. Use Val_Read to read in the value, which
; is either going to be a constant or a symbol reference, and then continue into
; LoadImmediate_Done.
; Value reading doesn't end until end of line, so we need to wrap up with
; EndOfLine_Continue once that's done.
  :LineStart_LoadImmediate
@ :LoadImmediate_Done
D = 0|A
@ &val/next
M = 0|D
~jmp,:Val_Read
~jmp,:MainLoop

  :LoadImmediate_Done
@ &val/value
D = 0|M
@ &core/opcode
M = 0|D
~jmp,:EndOfLine_Continue

; Called when the line starts with :, denoting a label definition.
; If in the first pass, we transfer control to ReadLabel
; else treat it like a comment.
  :LineStart_Label
@ &core/pass
D = 0|M
; On pass 1, call CommentStart, the same routine used by the main loop when it
; sees a ';' character. This will flag this character, and the rest of the line,
; as a comment.
@ :CommentStart
= 0|D <>
; On pass 0, we need to actually read in the label and associate a value with it.
; Sym_Read will take over the state machine until it's done reading in the
; label, then call sym_next, which we will point at BindPC to associate the
; label with the current program counter.
@ :BindPC
D = 0|A
@ &sym/next
M = 0|D
~jmp,:Sym_Read

; Called when we have successfully read in a label definition. This should in
; practice be called at end of line via Sym_Read, so char=\0 and EndOfLine_Continue
; is waiting for us.
; So, we need to:
; - set sym_next to EndOfLine_Continue, so Sym_Bind jumps straight there
;   once we're done
; - copy PC into sym_value and then call Sym_Bind.
  :BindPC
; set up sym_next
@ :EndOfLine_Continue
D = 0|A
@ &sym/next
M = 0|D
; set up PC
@ &core/pc
D = 0|M
@ &sym/value
M = 0|D
~jmp,:Sym_Bind

; Called when the line starts with & or #, denoting a constant definition.
; We need to call Sym_Read to read the symbol hash into &symbol, then Val_Read
; to read the value into &value, then copy &value to &sym_value and call Sym_Bind
; to commit the binding.
; Sym_Read will end when it's passed an = by the main loop, which is still going
; to be in the char buffer, but it's safe to call Val_Read next because it only
; sets up the state and returns control.
; Note that you cannot alias symbols, e.g. `#foo = #bar` is illegal and your
; program will be frogs.
  :LineStart_Constant
@ :LineStart_Constant_ReadVal
D = 0|A
@ &sym/next
M = 0|D
~jmp,:Sym_Read

  :LineStart_Constant_ReadVal
@ :LineStart_Constant_Bind
D = 0|A
@ &val/next
M = 0|D
~jmp,:Val_Read

; sym_value = value; sym_next = EndOfLine_Continue; jmp Sym_Bind
  :LineStart_Constant_Bind
@ &val/value
D = 0|M
@ &sym/value
M = 0|D
@ :EndOfLine_Continue
D = 0|A
@ &sym/next
M = 0|D
~jmp,:Sym_Bind

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Destination state                                                          ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; State for reading the optional A, D, and M at the start of an instruction,
; designating the destination(s) for the computed values.
  :Destination
; Check for =, which sends us to the next state (LHS)
@ &core/char
D = 0|M
@ 075 ; '='
D = D-A
@ :Destination_Finished
= 0|D =
; Check for A.
@ &core/char
D = 0|M
@ 0101 ; 'A'
D = D-A
@ :Destination_A
= 0|D =
; Check for D.
@ &core/char
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :Destination_D
= 0|D =
; Check for M.
@ &core/char
D = 0|M
@ 0115 ; 'M'
D = D-A
@ :Destination_M
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
~jmp,:Error

; We read an =, so set up the state transition.
  :Destination_Finished
@ :LHS
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

; The next three short procedures all set up D with the correct bit to set in
; the instruction and then jump to Destination_SetBits, which does the actual
; modification of the opcode.
  :Destination_A
@ 040 ; 0x0020
D = 0|A
~jmp,:Destination_SetBits
  :Destination_D
@ 020 ; 0x0010
D = 0|A
~jmp,:Destination_SetBits
  :Destination_M
@ 010 ; 0x0008
D = 0|A
; fall through
; The bit we want is in D, so bitwise-or it into the opcode
  :Destination_SetBits
@ &core/opcode
M = D | M
~jmp,:MainLoop

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
  :LHS
; Check for A.
@ &core/char
D = 0|M
@ 0101 ; 'A'
D = D-A
@ :LHS_A
= 0|D =
; Check for D.
@ &core/char
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :LHS_Done
= 0|D =
; Check for M.
@ &core/char
D = 0|M
@ 0115 ; 'M'
D = D-A
@ :LHS_M
= 0|D =
; Check for 0.
@ &core/char
D = 0|M
@ 060 ; '0'
D = D-A
@ :LHS_Z
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
~jmp,:Error

; Operand is 0, set the zx bit.
  :LHS_Z
@ 0200 ; 0x0080
D = 0|A
~jmp,:LHS_SetBits

; Operand is M, set the mr bit and fall through the LHS_A to set the sw bit.
  :LHS_M
@ 010000 ; 0x1000
D = 0|A
; fall through to LHS_A.

; Operand is A, set the sw bit.
  :LHS_A
@ 0100 ; 0x1000
; Use | here so that the fallthrough case from LHS_M works as expected.
; If we came from LHS proper, D is guaranteed to be zero because we JEQ'd.
D = D|A

; D contains some pile of bits. Set them in the opcode.
  :LHS_SetBits
@ &core/opcode
M = D | M
; fall through
  :LHS_Done
@ :Operator
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

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
  :Operator
; add
@ &core/char
D = 0|M
@ 053 ; '+'
D = D-A
@ :Operator_Add
= 0|D =
; sub
@ &core/char
D = 0|M
@ 055 ; '-'
D = D-A
@ :Operator_Sub
= 0|D =
; and
@ &core/char
D = 0|M
@ 046 ; &
D = D-A
@ :Operator_And
= 0|D =
; or
@ &core/char
D = 0|M
@ 0174 ; '|'
D = D-A
@ :Operator_Or
= 0|D =
; xor
@ &core/char
D = 0|M
@ 0136 ; '^'
D = D-A
@ :Operator_Xor
= 0|D =
; not
@ &core/char
D = 0|M
@ 041 ; '!'
D = D-A
@ :Operator_Not
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
~jmp,:Error

; Helpers for the various ALU operations. Same deal as LHS here, they
; set the bits needed in D and then jump to SetBits to actually move
; them into the opcode.
  :Operator_Add
@ 02000 ; 0x0400
D = 0|A
~jmp,:Operator_SetBits
  :Operator_Sub
@ 03000 ; 0x0600
D = 0|A
~jmp,:Operator_SetBits
  :Operator_And
D = 0&A
~jmp,:Operator_SetBits
  :Operator_Or
@ 0400 ; 0x0100
D = 0|A
~jmp,:Operator_SetBits
  :Operator_Xor
@ 01000 ; 0x0200
D = 0|A
~jmp,:Operator_SetBits

; This gets special handling because we need to skip the second operand
; entirely, since not is a unary operation.
  :Operator_Not
@ 01400 ; 0x0300
D = 0|A
@ &core/opcode
M = D | M
@ :Jump
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

; Write bits to opcode, set next state to RHS, return to main loop.
  :Operator_SetBits
@ &core/opcode
M = D | M
@ :RHS
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

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
  :RHS
; Check for A. This is the default case, so we set no bits.
@ &core/char
D = 0|M
@ 0101 ; 'A'
D = D-A
@ :RHS_Done
= 0|D =
; Check for D.
@ &core/char
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :RHS_D
= 0|D =
; Check for M.
@ &core/char
D = 0|M
@ 0115 ; 'M'
D = D-A
@ :RHS_M
= 0|D =
; Check for 1.
@ &core/char
D = 0|M
@ 061 ; '1'
D = D-A
@ :RHS_One
= 0|D =
; If char is \0 we're at end of line, no special cleanup needed so just continue
; EOL handling.
@ &core/char
D = 0|M
@ :EndOfLine_Continue
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
~jmp,:Error

; D operand means we need to set the swap bit (and the first operand should
; have been 0, A, or M, but we don't check that here. An appropriate check
; would be that either sw or zx is already set.)
  :RHS_D
@ 0100 ; 0x0040
D = 0|A
~jmp,:RHS_SetBits

; Operand is M, set the mr bit.
  :RHS_M
@ 010000 ; 0x1000
D = 0|A
~jmp,:RHS_SetBits

; Operand is 1, set op0 to turn add into inc and sub into dec.
; If the operator was not add or sub your machine code will be frogs.
  :RHS_One
@ 0400 ; 0x0100
D = 0|A
; Fall through

; D contains some pile of bits. Set them in the opcode.
  :RHS_SetBits
@ &core/opcode
M = D | M
; fall through

; Set next state to Jump and we're done here.
  :RHS_Done
@ :Jump
D = 0|A
@ &core/state
M = 0|D
~jmp,:MainLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Jump state                                                                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Handler for the jump flags. These go at the end of the instruction and consist
; of some combination of the <, =, and > characters, which directly set the lt,
; eq, and gt bits in the opcode.
; This has the same structure as the LHS/RHS states: check character, set bit
; in opcode. Unlike those states it doesn't proceed to a new state afterwards;
; the assembler sits in this state until the end of the line is reached.
  :Jump
; less than
@ &core/char
D = 0|M
@ 074 ; '<'
D = D-A
@ :Jump_LT
= 0|D =
; equal
@ &core/char
D = 0|M
@ 075 ; '='
D = D-A
@ :Jump_EQ
= 0|D =
; greater than
@ &core/char
D = 0|M
@ 076 ; '>'
D = D-A
@ :Jump_GT
= 0|D =
; If char is \0 we're at end of line, no special cleanup needed so just continue
; EOL handling.
@ &core/char
D = 0|M
@ :EndOfLine_Continue
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
~jmp,:Error

  :Jump_LT
@ 04 ; 0x0004
D = 0|A
~jmp,:Jump_SetBits
  :Jump_EQ
@ 02 ; 0x0002
D = 0|A
~jmp,:Jump_SetBits
  :Jump_GT
@ 01 ; 0x0001
D = 0|A
~jmp,:Jump_SetBits

; D contains some pile of bits. Set them in the opcode and remain in the same
; state.
  :Jump_SetBits
@ &core/opcode
M = D | M
~jmp,:MainLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of program stuff                                                       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Success state. Writes out the symbol table to the end of the ROM so that
; debug tools can read it, although they'll also need access to the source code
; since the symbols are stored as hashes.
; End of ROM symbol table format is the contents of the symbol table, two words
; at a time, followed by a word containing the number of table entries.
  :Finalize
~call,:Sym_Dump,0
~drop
~jmp,:Exit

; Error state. Write the input line number as a word, then the current pass
; as a byte.
; External tools will be able to tell something went wrong because the ROM will
; have an odd number of bytes in it, and a well-formed image should always be
; word-aligned.
  :Error
@ &core/line-num
D = 0|M
@ &stdout.words
M = 0|D
@ &core/pass
D = 0|M
@ &stdout.bytes
M = 0|D
; fall through to Exit

  :Exit
; Jump off the end of ROM
@ $7FFF
= 0|D <=>

; To support labels we need a number of new features:
; - understanding ":foo" as defining a label foo at the address at which it occurs
; - understanding "@ :foo" as loading A with the value recorded for the label foo
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

