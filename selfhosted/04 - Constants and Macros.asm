;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 0_init.asm
;; Variable declarations and initialization routines.
;; The name starts with 0_ so that when concatenating the various asm files
;; to get the input to the assembler, this comes first.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
; Number of current line. Used for error reporting.
:&line.

; Whether we're on the first pass (0) or the second pass (1).
; There are more elegant ways to do this but I can implement those once we have
; label support working. :)
:&pass.

; Program counter. Used to generate labels.
:&pc.
; Offset in source file. Used to generate macros.
:&fseek.

; Memory-mapped IO we still need to hard-code until we have define, using labels
; as variables only works for stuff where we don't care exactly where it ends up.
;DEFINE &stdin_status 0x7FF0
;DEFINE &stdin 0x7FF1
;DEFINE &stdout_bytes 0x7FF9
;DEFINE &stdout 0x7FFA

; Entry point
@ :Init.
= 0+D <=>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; macros.asm
;; Support for assembler macros.
;;
;; A macro is an entry in the symbol table like anything else; however, rather
;; than being bound to an address in ROM (as labels do) or a programmer-supplied
;; value (as constants do), the name of a macro is bound to the offset in the
;; source file where the first line of the macro definition begins.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Flag to determine if we're in the middle of a macroexpansion, and should jump
; back to the callsite when we reach the end.
:&in_macroexpansion.

; Address of the macro we are about to invoke once we finish reading the
; arguments.
:&macro_address.

; Pointer to macro argument we're currently reading in.
:&macro_argp.

; Stack of macro callsites and arguments. A stack frame consists of the offset
; in the file at which the macroexpansion was invoked (i.e. where we need to
; seek back to when expansion finishes). SP points to the next *unused* stack
; slot.
:&macro_sp.
:&macro_stack.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macro_Begin
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by LineStart when it sees the start of a macro definition.
  :Macro_Begin.
; First, read in the name of the macro.
@ :Macro_Begin_Bind.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

; Called when the name of the macro is done being read in. This should only
; happen on EOL, so we record the current offset as the macro's value, which
; means a seek back to this point will put us at the start of the first line
; in the macro body.
  :Macro_Begin_Bind.
; If we're on the second pass, do nothing here; the name of the macro is already
; in the symbol table and code generation will emit a no-op.
@ :&pass.
D = 0|M
@ :EndOfLine_Continue.
= 0|D <>
; Otherwise we need to bind it. Set the continuation to EndOfLine_Continue,
; which is conveniently already in A.
D = 0|A
@ :&sym_next.
M = 0|D
; Now set the value to the current file offset.
@ :&fseek.
D = 0|M
@ :&sym_value.
M = 0|D
@ :Sym_Bind.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macro_End
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by LineStart when we hit the end of a macro. If this is the end of a
; macro definition we have nothing to do here except ignore it; however, if we
; got here via a macroexpansion, we need to clean up after ourselves and seek
; the input file back to where we came from.
  :Macro_End.
; Not in macroexpansion? Return to mainloop.
@ :&in_macroexpansion.
D = 0|M
@ :MainLoop.
= 0|D =
; If we get this far we're in a macroexpansion. Decrement the macroexpansion
; flag and seek back to the point at which we were called.
; Note that this does not call EndOfLine_Continue -- as far as the main loop
; is concerned, it read a ] which was ignored and then it read the rest of the
; line we seek back to.
@ :&in_macroexpansion.
M = M-1
; decrement macro stack pointer and restore previous fseek value
@ :&macro_sp.
M = M-1
A = 0|M
D = 0|M
@ :&fseek.
M = 0|D
@ 077760 ; &stdin_status
M = 0|D ; seek
; drop this whole stack frame
@ 012
D = 0|A
@ :&macro_sp.
M = M-D
@ :MainLoop.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macro_Expand
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by LineStart when it sees a macroexpansion.
  :Macro_Expand.
; Step one, resolve the macro. Pretend the first character is [ so that it matches
; the symbol seen at macro definition time.
@ 0133 ; '['
D = 0|A
@ :&char.
M = 0|D
@ :Macro_Expand_Resolve.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

; Called after reading in the macro name.
  :Macro_Expand_Resolve.
@ :Macro_Expand_ResolveDone.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Resolve.
= 0|D <=>

; At this point sym_val holds the file offset of the macro definition.
; We need to set the in_macroexpansion flag and seek back to that point
; in the input file, which will cause the contents of the macro to be assembled
; into the output stream.
; TODO: macro argument support -- check if &char is \0 (eol) or , and if the
; latter, after resolving, do a Val_Read and set that as the macro argument.
  :Macro_Expand_ResolveDone.
@ :&sym_value.
D = 0|M
@ :&macro_address.
M = 0|D ; copy the resolved value into macro_address
@ :&char.
D = 0|M
@ :Macro_Expand_Call.
= 0|D = ; if char is \0, no arguments, call immediately
; there must be arguments, so start reading them with Val_Read
  :Macro_Expand_WithArguments.
@ :&macro_sp.
D = 0|M
@ :&macro_argp.
M = 0|D ; set argp to point at the start of the current macro stack frame
@ :Macro_Expand_ArgDone.
D = 0|A
@ :&val_next.
M = 0|D
@ :Val_Read.
= 0|D <=>

; We just finished reading in an argument, so store it in the next argv slot,
; increment argp, and either read another one or invoke the macro depending
; on whether we're at EOL or not.
  :Macro_Expand_ArgDone.
@ :&value.
D = 0|M
@ :&macro_argp.
A = 0|M
M = 0|D
@ :&macro_argp.
M = M+1
@ :&char. ; char = \0? end of line, so call the macro
D = 0|M
@ :Macro_Expand_Call.
= 0|D =
; otherwise look for another argument!
@ :Macro_Expand_ArgDone.
D = 0|A
@ :&val_next.
M = 0|D
@ :Val_Read.
= 0|D <=>

; Called to actually invoke the macro once we've read in the macro address and
; all the arguments, if any.
  :Macro_Expand_Call.
@ :&in_macroexpansion.
M = M+1
; Advance the macro stack pointer 11 words (10 arguments + return address)
@ 013
D = 0|A
@ :&macro_sp.
M = M+D
; push the current fseek onto the macro stack. The pointer points at the first
; empty slot, so we need to subtract 1 from it to get the right address.
@ :&fseek.
D = 0|M
@ :&macro_sp.
A = M-1
M = 0|D ; store current fseek at top of macro stack
; seek to the address of the macro definition
@ :&macro_address.
D = 0|M
@ 077760 ; stdin_status
M = 0|D
@ :&fseek.
M = 0|D
; We jump back to mainloop here because the line containing the macroexpansion
; should be replaced with the first line of the macro, not with a no-op
; but this means that the state is still set to Sym_Read
; so instead we want to jump to NewInstruction to reset the state pointer, etc.
@ :NewInstruction.
= 0|D <=>
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
@ :&line.  ; initialize line number to 1
M = 0+1
; initialize macroexpansion stack
@ :&macro_stack.
D = 0|A
@ :&macro_sp.
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
@ 040000 ;16384
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
@ 077760 ; &stdin_status
D = 0|M
@ :NextPass.
= 0|D =
; Read next byte of input and stash it in char
@ 077761 ; &stdin
D = 0|M
@ :&char.
M = 0|D
; Increment the fseek counter
@ :&fseek.
M = M+1
; If it's a newline, run the end-of-line routine.
@ :&char.
D = 0|M
@ 012
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
@ 040
D = D - A
@ :MainLoop.
= 0|D =
; If it's a start-of-comment character, run CommentStart to set the in_comment flag
@ :&char.
D = 0|M
@ 073
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
@ :Finalize.
= 0|D >
; Otherwise, rewind stdin to start of file by writing a 0 to it
@ 077760 ; &stdin_status
M = 0&D
; Reset the program counter to 0
@ :&pc.
M = 0&D
; And the seek point
@ :&fseek.
M = 0&D
; Then increment pass, reset the line counter, and restart the main loop.
@ :&pass.
M = M+1
@ :&line.
M = 0+1
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
; If we're in a macro, don't increment line number
@ :in_macroexpansion.
D = 0|M
@ :EndOfLine_NoLineNum.
= 0|D <>
@ :&line.
M = M+1
  :EndOfLine_NoLineNum.
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
@ 077772 ; &stdout
M = 0|D
; Also increment PC, since relative jumps are calculated on the second pass.
@ :&pc.
M = M+1
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
@ 0100 ; '@'
D = D-A
@ :LineStart_LoadImmediate.
= 0|D =
; If it's a :, this is a label definition and we branch further depending on
; what pass we're on.
@ :&char.
D = 0|M
@ 072 ; ':'
D = D-A
@ :LineStart_Label.
= 0|D =
; If it's a &, this is a constant definition - we need to read the label, then
; the value.
@ :&char.
D = 0|M
@ 046 ; '&'
D = D-A
@ :LineStart_Constant.
= 0|D =
; Same deal with # as with &.
@ :&char.
D = 0|M
@ 043 ; '#'
D = D-A
@ :LineStart_Constant.
= 0|D =
; If it's a [, this is the start of a macro definition.
@ :&char.
D = 0|M
@ 0133 ; '['
D = D-A
@ :Macro_Begin.
= 0|D =
; If it's a ], this is the end of a macro definition.
@ :&char.
D = 0|M
@ 0135 ; ']'
D = D-A
@ :Macro_End.
= 0|D =
; If it's a ~, this is a macro invokation
@ :&char.
D = 0|M
@ 0176 ; '~'
D = D-A
@ :Macro_Expand.
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

; Called when the line starts with @. Use Val_Read to read in the value, which
; is either going to be a constant or a symbol reference, and then continue into
; LoadImmediate_Done.
; Value reading doesn't end until end of line, so we need to wrap up with
; EndOfLine_Continue once that's done.
  :LineStart_LoadImmediate.
@ :LoadImmediate_Done.
D = 0|A
@ :&val_next.
M = 0|D
@ :Val_Read.
= 0|D <=>
@ :MainLoop.
= 0|D <=>

  :LoadImmediate_Done.
@ :&value.
D = 0|M
@ :&opcode.
M = 0|D
@ :EndOfLine_Continue.
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
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

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

; Called when the line starts with & or #, denoting a constant definition.
; We need to call Sym_Read to read the symbol hash into &symbol, then Val_Read
; to read the value into &value, then copy &value to &sym_value and call Sym_Bind
; to commit the binding.
; Sym_Read will end when it's passed an = by the main loop, which is still going
; to be in the char buffer, but it's safe to call Val_Read next because it only
; sets up the state and returns control.
; Note that you cannot alias symbols, e.g. `#foo = #bar` is illegal and your
; program will be frogs.
  :LineStart_Constant.
@ :LineStart_Constant_ReadVal.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Read.
= 0|D <=>

  :LineStart_Constant_ReadVal.
@ :LineStart_Constant_Bind.
D = 0|A
@ :&val_next.
M = 0|D
@ :Val_Read.
= 0|D <=>

; sym_value = value; sym_next = EndOfLine_Continue; jmp Sym_Bind
  :LineStart_Constant_Bind.
@ :&value.
D = 0|M
@ :&sym_value.
M = 0|D
@ :EndOfLine_Continue.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Bind.
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
@ 075 ; '='
D = D-A
@ :Destination_Finished.
= 0|D =
; Check for A.
@ :&char.
D = 0|M
@ 0101 ; 'A'
D = D-A
@ :Destination_A.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :Destination_D.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 0115 ; 'M'
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
@ 040 ; 0x0020
D = 0|A
@ :Destination_SetBits.
= 0|D <=>
  :Destination_D.
@ 020 ; 0x0010
D = 0|A
@ :Destination_SetBits.
= 0|D <=>
  :Destination_M.
@ 010 ; 0x0008
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
@ 0101 ; 'A'
D = D-A
@ :LHS_A.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :LHS_Done.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 0115 ; 'M'
D = D-A
@ :LHS_M.
= 0|D =
; Check for 0.
@ :&char.
D = 0|M
@ 060 ; '0'
D = D-A
@ :LHS_Z.
= 0|D =
; None of the above branches worked, so we're looking at something we don't
; understand and should abort the program.
@ :Error.
= 0|D <=>

; Operand is 0, set the zx bit.
  :LHS_Z.
@ 0200 ; 0x0080
D = 0|A
@ :LHS_SetBits.
= 0|D <=>

; Operand is M, set the mr bit and fall through the LHS_A to set the sw bit.
  :LHS_M.
@ 010000 ; 0x1000
D = 0|A
; fall through to LHS_A.

; Operand is A, set the sw bit.
  :LHS_A.
@ 0100 ; 0x1000
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
@ 053 ; '+'
D = D-A
@ :Operator_Add.
= 0|D =
; sub
@ :&char.
D = 0|M
@ 055 ; '-'
D = D-A
@ :Operator_Sub.
= 0|D =
; and
@ :&char.
D = 0|M
@ 046 ; &
D = D-A
@ :Operator_And.
= 0|D =
; or
@ :&char.
D = 0|M
@ 0174 ; '|'
D = D-A
@ :Operator_Or.
= 0|D =
; xor
@ :&char.
D = 0|M
@ 0136 ; '^'
D = D-A
@ :Operator_Xor.
= 0|D =
; not
@ :&char.
D = 0|M
@ 041 ; '!'
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
@ 02000 ; 0x0400
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Sub.
@ 03000 ; 0x0600
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_And.
D = 0&A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Or.
@ 0400 ; 0x0100
D = 0|A
@ :Operator_SetBits.
= 0|D <=>
  :Operator_Xor.
@ 01000 ; 0x0200
D = 0|A
@ :Operator_SetBits.
= 0|D <=>

; This gets special handling because we need to skip the second operand
; entirely, since not is a unary operation.
  :Operator_Not.
@ 01400 ; 0x0300
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
@ 0101 ; 'A'
D = D-A
@ :RHS_Done.
= 0|D =
; Check for D.
@ :&char.
D = 0|M
@ 0104 ; 'D'
D = D-A
@ :RHS_D.
= 0|D =
; Check for M.
@ :&char.
D = 0|M
@ 0115 ; 'M'
D = D-A
@ :RHS_M.
= 0|D =
; Check for 1.
@ :&char.
D = 0|M
@ 061 ; '1'
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
@ 0100 ; 0x0040
D = 0|A
@ :RHS_SetBits.
= 0|D <=>

; Operand is M, set the mr bit.
  :RHS_M.
@ 010000 ; 0x1000
D = 0|A
@ :RHS_SetBits.
= 0|D <=>

; Operand is 1, set op0 to turn add into inc and sub into dec.
; If the operator was not add or sub your machine code will be frogs.
  :RHS_One.
@ 0400 ; 0x0100
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
@ 074 ; '<'
D = D-A
@ :Jump_LT.
= 0|D =
; equal
@ :&char.
D = 0|M
@ 075 ; '='
D = D-A
@ :Jump_EQ.
= 0|D =
; greater than
@ :&char.
D = 0|M
@ 076 ; '>'
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
@ 04 ; 0x0004
D = 0|A
@ :Jump_SetBits.
= 0|D <=>
  :Jump_EQ.
@ 02 ; 0x0002
D = 0|A
@ :Jump_SetBits.
= 0|D <=>
  :Jump_GT.
@ 01 ; 0x0001
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

; Success state. Writes out the symbol table to the end of the ROM so that
; debug tools can read it, although they'll also need access to the source code
; since the symbols are stored as hashes.
; End of ROM symbol table format is the contents of the symbol table, two words
; at a time, followed by a word containing the number of table entries.
  :Finalize.
@ :Sym_Dump.
= 0|D <=>

; Error state. Write the input line number as a word, then the current pass
; as a byte.
; External tools will be able to tell something went wrong because the ROM will
; have an odd number of bytes in it, and a well-formed image should always be
; word-aligned.
  :Error.
@ :&line.
D = 0|M
@ 077772 ; &stdout_words
M = 0|D
@ :&pass.
D = 0|M
@ 077771 ; &stdout_bytes
M = 0|D
; fall through to Exit

  :Exit.
; Jump off the end of ROM
@ 077777
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; symbols.asm
;; Code for the symbol table:
;; - parsing symbols from input
;; - binding symbols to values
;; - resolving symbols
;; This will be used for labels, constants, and macros.
;;
;; It exports three procedures:
;; - Sym_Read, which activates a parser state for reading a symbol
;; - Sym_Bind, which creates a new entry in the symbol table
;; - Sym_Resolve, which looks up a symbol table entry
;; And three variables: &symbol, &sym_value, and &sym_next.
;; See the comments below for details on how to use these.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Public Variables ;;;;

; Contains the hash of the current symbol. Read fills this in; Bind and
; Resolve both read it.
:&symbol.

; Contains the value associated with a symbol. Bind reads it to get the symbol's
; value when creating a new binding, Resolve
:&sym_value.

; Continuation. Since Read, Bind, and Resolve all get called by multiple places
; in the parser, and we don't actually have functions or, really, a stack at all
; yet, it is assumed that the caller will drop the address of the next procedure
; to call into this variable. Once one of these utility functions/states is done
; (for Bind/Resolve, when they complete, and for Read, once it reaches the end of
; the symbol input), it will *immediately* jump to whatever address this points
; to.
; Although note that on symbol resolution failure it will instead jump to Error.
:&sym_next.

;;;; Private Variables ;;;;
; These are internal workings of the symbol table; do not touch!

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
; it overwriting one of our other vars!
;:&symbols.
; This turns out not to be large enough, so it gets shoved to zz-postscript
; instead.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Read                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is responsible for reading a symbol from input and leaving its hash in
; symbol. At the end of reading it calls sym_next; whatever code that points
; to is responsible for doing something with the hash, probably either calling
; Bind or Resolve.
;
; Callers are expected to call it directly; it will update the state pointer
; itself. This allows it to set up internal structures it needs correctly.
  :Sym_Read.
; Clear the symbol hash
@ :&symbol.
M = 0&D
; Update state pointer
@ :Sym_Read_State.
D = 0|A
@ :&state.
M = 0|D
; fall through to Sym_Read_State

; This is the actual state. It receives each individual character.
; First, if we're at the end of the symbol -- EOL or the '=' or ',' characters --
; it should jump to sym_next.
; Note that it doesn't go straight to EndOfLine_Continue at end of line -- the
; *caller* is responsible for that!
  :Sym_Read_State.
; check for end of line
@ :&char.
D = 0|M
@ :&sym_next.
A = 0|M
= 0|D =
; check for comma and equals
@ :&char.
D = 0|M
@ 054 ; ','
D = D-A
@ :&sym_next.
A = 0|M
= 0|D =
; check for end of line
@ :&char.
D = 0|M
@ 075 ; '='
D = D-A
@ :&sym_next.
A = 0|M
= 0|D =
; Not at end, so add the just-read character to the label hash.
; First, double the existing hash to shift left 1 bit.
@ :&symbol.
D = 0|M
D = D+M
; Then add the new character to it.
@ :&char.
D = D+M
@ :&symbol.
M = 0|D
; return to main loop
@ :MainLoop.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Bind                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by the first-pass compiler to bind symbols to values. It expects the
; symbol hash in symbol and the associated value in sym_value.
; Note that no error checking is performed; in particular there is nothing to
; stop you from re-using a variable name, and if you do, only one of the bindings
; will take effect FOR THE ENTIRE PROGRAM.
;
; This is not a parser state; you call it and it does its work and then immediately
; calls *sym_next.
  :Sym_Bind.
; last_sym should already be pointing to the free slot at the end of the symbol
; table, so write the hash to it
@ :&symbol.
D = 0|M ; D = symbol
@ :&last_sym.
A = 0|M
M = 0|D ; *last_sym = D
; increment last_sym so it points to the value slot
@ :&last_sym.
M = M+1
; write the value we were given to that slot
@ :&sym_value.
D = 0|M
@ :&last_sym.
A = 0|M
M = 0|D
; increment last_sym again so it points to the next, unused slot
@ :&last_sym.
M = M+1
; call sym_next
@ :&sym_next.
A = 0|M
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Resolve                                                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by the second-pass compiler (and once we have macros, the first-pass as
; well) when resolving a symbol. It expects the symbol hash in *symbol and will
; leave the value in *sym_value. If the symbol cannot be resolved it jumps to Error.
;
; Like Sym_Bind it is not a state; you call it and it does its work immediately
; and then calls sym_next.
;
; A common pattern is going to be something like:
;   :MyState
;   [if we are reading a symbol:]
;   [put MyState_Resolve in sym_next]
;   @ :Sym_Read
;   JMP
;   :MyState_Resolve
;   [put MyState_ResolveDone in sym_next]
;   @ :Sym_Resolve
;   JMP
;   :MyState_ResolveDone
;   [code to do something with the resolved value]
  :Sym_Resolve.
; Startup code - set this_sym = &symbols
@ :&symbols.
D = 0|A
@ :&this_sym.
M = 0|D
  :Sym_Resolve_Loop.
; Are we at the end of the symbol table? If so, error out.
@ :&last_sym.
D = 0|M
@ :&this_sym.
D = D-M
@ :Sym_Resolve_Error.
= 0|D =
; Check if the current symbol is the one we're looking for.
@ :&this_sym.
A = 0|M ; fixed?
D = 0|M
@ :&symbol.
D = D-M
@ :Sym_Resolve_Success.
= 0|D =
; It wasn't :( Advance this_sym by two to point to the next entry, and loop.
@ :&this_sym.
M = M+1
M = M+1
@ :Sym_Resolve_Loop.
= 0|D <=>

; Called when we successfully find an entry in the symbol table. this_sym holds
; a pointer to the label cell of the entry, so we need to inc it to get the
; value cell.
  :Sym_Resolve_Success.
@ :&this_sym.
A = M+1
D = 0|M
; now write the value into &sym_value so the caller can fetch it
@ :&sym_value.
M = 0|D
; return control to the caller
@ :&sym_next.
A = 0|M
= 0|D <=>

; Called when we cannot find the requested symbol in the table.
; On pass 1 we may have just not seen the symbol definition yet, so instead we
; return whatever is currently in sym_value.
; On pass 2, we error out.
  :Sym_Resolve_Error.
@ :&pass.
D = 0|M
@ :&sym_next.
A = 0|M
= 0|D =
; pass != 0, raise an error.
@ :Error.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Resolve                                                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called at the end of the program, after successfully writing a ROM image.
; Dumps the symbol table to stdout in a debugger-friendly format.
  :Sym_Dump.
@ :&symbols.
D = 0|A
@ :&this_sym.
M = 0|D
  :Sym_Dump_Iter.
; this_sym == last_sym? break
@ :&this_sym.
D = 0|M
@ :&last_sym.
D = D-M
@ :Sym_Dump_Done.
= 0|D =
; else dump next table entry and increment this_sym
@ :&this_sym.
A = 0|M
D = 0|M
@ 077772 ; &stdout_words
M = 0|D
@ :&this_sym.
M = M+1
@ :Sym_Dump_Iter.
= 0|D <=>
  :Sym_Dump_Done.
; write total symbol count and then exit program
@ :&symbols.
D = 0|A
@ :&last_sym.
D = M-D
@ 077772 ; &stdout_words
M = 0|D
@ :Exit.
= 0|D <=>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; values.asm
;;
;; Code for reading values from the source code, e.g. those used with the load
;; immediate instructions.
;;
;; It supports:
;; - character literals ('a)
;; - decimal literals (123)
;; - hex literals ($123)
;; - relative program counter offsets (-n or +n)
;; - and symbols, starting with [&#:], which are delegated to Sym_Read
;;
;; It exports one procedure: Val_Read, which activates a parser state for
;; reading a value. Upon completion it calls the procedure pointed to by
;; val_next.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Public Variables ;;;;

; The value just read.
:&value.

; The continuation to call once the value is read.
:&val_next.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Val_Read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  :Val_Read.
; Clear the value buffer.
@ :&value.
M = 0&D
; Update state pointer
@ :Val_Read_State.
D = 0|A
@ :&state.
M = 0|D
; This is called when we know the next token is going to be a value, so we just
; return control to the mainloop. Val_Read_State will transfer control to
; subsidiary states as needed.
@ :MainLoop.
= 0|D <=>

; This is the master value-reading state. It will transfer control to a secondary
; state based on the first character sees; a :, &, or # means a symbol reference
; which must be resolved, a ' means a character constant, a $ means a hexadecimal
; constant, a 0 means an octal constant, ~ and % mean macro expansion and
; argument splicing, and anything else we optimistically assume is a decimal constant.
  :Val_Read_State.
; First, check for ':', '&', and '#'. These all immediately transfer control to
; Sym_Read, so we set up the continuation for those ahead of time.
@ :Val_Read_SymDone.
D = 0|A
@ :&sym_next.
M = 0|D
; Now check the actual characters
@ :&char.
D = 0|M
@ 072 ; ':'
D = D-A
@ :Sym_Read.
= 0|D =
@ :&char.
D = 0|M
@ 043 ; '#'
D = D-A
@ :Sym_Read.
= 0|D =
@ :&char.
D = 0|M
@ 046 ; '&'
D = D-A
@ :Sym_Read.
= 0|D =
; Now check for a character constant.
@ :&char.
D = 0|M
@ 047 ; "'"
D = D-A
@ :Val_Read_Char.
= 0|D =
; Relative jump address backwards?
@ :&char.
D = 0|M
@ 055 ; '-'
D = D-A
@ :Val_Read_RelativeJump_Back.
= 0|D =
; Relative jump address forwards?
@ :&char.
D = 0|M
@ 053 ; '+'
D = D-A
@ :Val_Read_RelativeJump_Forward.
= 0|D =
; Hex constant starting with $?
@ :&char.
D = 0|M
@ 044 ; '$'
D = D-A
@ :Val_Read_Hex.
= 0|D =
; Octal constant starting with 0?
@ :&char.
D = 0|M
@ 060 ; '0'
D = D-A
@ :Val_Read_Oct.
= 0|D =
; Macroexpansion argument?
@ :&char.
D = 0|M
@ 045 ; '%'
D = D-A
@ :Val_Read_MacroArg.
= 0|D =
; None of the above? Assume it's a decimal constant. Set that as the current
; state and then jump to it to process the first character.
@ :Val_Read_Dec.
D = 0|A
@ :&state.
M = 0|D
@ :Val_Read_Dec.
= 0|D <=>


; Called after reading in a symbol. We need to call Sym_Resolve to get the
; associated value.
  :Val_Read_SymDone.
@ :Val_Read_SymResolved.
D = 0|A
@ :&sym_next.
M = 0|D
@ :Sym_Resolve.
= 0|D <=>

; Sym_Resolve is finished so copy the value it resolved into value and return
; control to our caller.
  :Val_Read_SymResolved.
@ :&sym_value.
D = 0|M
@ :&value.
M = 0|D
@ :&val_next.
A = 0|M
= 0|D <=>

; The state for reading a character constant. Character constants have the
; format 'x and scan as the character code for x, so (e.g.) 'a is 97.
  :Val_Read_Char.
; Set ourself as the current state first
@ :Val_Read_Char.
D = 0|A
@ :&state.
M = 0+D
; If char is 0 we're at EOL and have nothing further to do
@ :&char.
D = 0|M
@ :&val_next.
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
@ :&char.
D = 0|M
@ 054 ; ','
D = D-A
@ :&val_next.
A = 0|M
= 0|D =
; Otherwise just copy char into the value buffer
@ :&char.
D = 0|M
@ :&value.
M = 0+D
@ :MainLoop.
= 0|D <=>

; These are for generating relative jump values. It is the same as decimal
; values except at the end, we must add or subtract it from the program counter.
; So we delegate this to Val_Read_Dec except we also set a flag indicating that
; at the end of reading the value it should apply the PC offset.
; So here's the flag:
  :&relative-jump-mode.
; And the procedures:
  :Val_Read_RelativeJump_Back.
@ :&relative-jump-mode.
M = 0-1
@ :Val_Read_Dec_State.
D = 0|A
@ :&state.
M = 0+D
@ :MainLoop.
= 0|D <=>

  :Val_Read_RelativeJump_Forward.
@ :&relative-jump-mode.
M = 0+1
@ :Val_Read_Dec_State.
D = 0|A
@ :&state.
M = 0+D
@ :MainLoop.
= 0|D <=>

; Called to read a macro argument. Read one decimal digit and return
; *(*macro_sp - 11 + digit).
  :Val_Read_MacroArg.
@ :Val_Read_MacroArg_State.
D = 0|A
@ :&state.
M = 0+D
@ :MainLoop.
= 0|D <=>

  :Val_Read_MacroArg_State.
; if at end of line, call the continuation
@ :&char.
D = 0|M
@ :&val_next.
A = 0|M
= 0|D =
; else read the corresponding argument into value
@ :&char.
D = 0|M
@ 060 ; '0'
D = D-A ; D contains the digit now, 0-9
@ 013
D = D-A ; subtract 11
@ :&macro_sp.
A = 0|M ; read current macro stack pointer
A = A+D ; add our offset, which is now between -11 and -2
D = 0|M ; dereference to read the value into D, then store it in value
@ :&value.
M = 0|D
; and then return to the main loop
@ :MainLoop.
= 0|D <=>

; Called by LoadImmediate on encountering the leading $ of a hex constant.
; Unlike DecimalConstant we don't want to ingest the first character of the
; constant (since $ is not a digit), so we just set ReadDigit as the current
; state and return to the main loop, which will start feeding it characters
; starting with the *next* character.
  :Val_Read_Hex.
@ :Val_Read_Hex_State.
D = 0|A
@ :&state.
M = 0+D
@ :MainLoop.
= 0|D <=>

; The state for reading a hex constant. This is equivalent to a decimal constant
; except that (a) we multiply by 16 instead of by 10 each digit and (b) we understand
; the digits A-F and a-f as corresponding to the values 10-15.
  :Val_Read_Hex_State.
; Check if we're at end of line, if so just do nothing
@ :&char.
D = 0|M
@ :&val_next.
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
@ :&char.
D = 0|M
@ 054 ; ','
D = D-A
@ :&val_next.
A = 0|M
= 0|D =
; Start by making room in the value buffer
@ :&value.
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
@ 0141 ; 'a'
D = D-A
@ :Val_Read_HexLower.
= 0|D >=
@ :&char.
D = 0|M
@ 0101 ; 'A'
D = D-A
@ :Val_Read_HexUpper.
= 0|D >=
@ :Val_Read_HexNumeric.
= 0|D <=>

  :. ; for some reason we need a dummy label here or the definition of the
  ; following label doesn't stick.
  :Val_Read_HexLower.
@ :&char.
D = 0|M
@ 0127 ; 'a' - 10
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

  :Val_Read_HexUpper.
@ :&char.
D = 0|M
@ 067 ; 'A' - 10
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

  :Val_Read_HexNumeric.
@ :&char.
D = 0|M
@ 060 ; '0'
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

; The state for reading the number in a load immediate instruction.
; The number is decimal, so for each digit, we multiply the existing number by
; 10 by repeated addition, then add the new digit to it.
  :Val_Read_Dec.
@ :Val_Read_Dec_State.
D = 0|A
@ :&state.
M = 0+D
; fall through to state

  :Val_Read_Dec_State.
; Check if we're at end of line. If so we may need to do processing for relative
; jumps before we generate the opcode, and in either case we should then call
; the val_next continuation.
@ :&char.
D = 0|M
@ :Val_Read_Dec_EOL.
= 0|D =
; If char is , this is an argument separator, same deal as EOL
@ :&char.
D = 0|M
@ 054 ; ','
D = D-A
@ :Val_Read_Dec_EOL.
= 0|D =
; Start by making room in the value buffer
@ :&value.
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
@ 060 ; '0'
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

  :Val_Read_Dec_EOL.
@ :&relative-jump-mode.
D = 0|M
M = 0&D ; clear the flag, we have the value saved in D
@ :Val_Read_Dec_JumpBack.
= 0|D <
@ :Val_Read_Dec_JumpForward.
= 0|D >
@ :Val_Read_Dec_Done.
= 0|D <=>

  :Val_Read_Dec_JumpBack.
@ :&pc.
D = 0|M
@ :&value.
M = D-M
@ :Val_Read_Dec_Done.
= 0|D <=>

  :Val_Read_Dec_JumpForward.
@ :&pc.
D = 0|M
@ :&value.
M = D+M
@ :Val_Read_Dec_Done.
= 0|D <=>

  :Val_Read_Dec_Done.
; call the continuation
@ :&val_next.
A = 0|M
= 0|D <=>

; The state for reading the number in a load immediate instruction.
; This is the reader for octal numbers, which we're probably going to remove
; but stays here for backwards compatibility.
  :Val_Read_Oct.
@ :Val_Read_Oct_State.
D = 0|A
@ :&state.
M = 0+D
; fall through to state

  :Val_Read_Oct_State.
; Check if we're at end of line, if so just do nothing
@ :&char.
D = 0|M
@ :&val_next.
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
@ :&char.
D = 0|M
@ 054 ; ','
D = D-A
@ :&val_next.
A = 0|M
= 0|D =
; Start by making room in the value buffer
@ :&value.
D = 0|M
; Add D to M 7 times for a total of x8
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
; Subtract '0' to get a value in the range 0-7
; or out of the range if the user typed in some sort of garbage, oh well
@ 060 ; '0'
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>
:&symbols.
