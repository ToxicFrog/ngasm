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
&macros/in-expansion = $10

; Address of the macro we are about to invoke once we finish reading the
; arguments.
&macros/address = $11

; Pointer to macro argument we're currently reading in.
&macros/argp = $12

; Stack of macro callsites and arguments. A stack frame consists of the offset
; in the file at which the macroexpansion was invoked (i.e. where we need to
; seek back to when expansion finishes). SP points to the next *unused* stack
; slot.
&macros/sp = $13
; this needs a lot of space, since each macro invokation takes 11 words on the
; stack.
&macros/stack = $3000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macro_Begin
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by LineStart when it sees the start of a macro definition.
  :Macro_Begin.
; First, read in the name of the macro.
@ :Macro_Begin_Bind.
D = 0|A
@ &sym/next
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
@ &core/pass
D = 0|M
@ :EndOfLine_Continue.
= 0|D <>
; Otherwise we need to bind it. Set the continuation to EndOfLine_Continue,
; which is conveniently already in A.
D = 0|A
@ &sym/next
M = 0|D
; Now set the value to the current file offset.
@ &core/fseek
D = 0|M
@ &sym/value
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
@ &macros/in-expansion
D = 0|M
@ :MainLoop.
= 0|D =
; If we get this far we're in a macroexpansion. Decrement the macroexpansion
; flag and seek back to the point at which we were called.
; Note that this does not call EndOfLine_Continue -- as far as the main loop
; is concerned, it read a ] which was ignored and then it read the rest of the
; line we seek back to.
@ &macros/in-expansion
M = M-1
; decrement macro stack pointer and restore previous fseek value
@ &macros/sp
M = M-1
A = 0|M
D = 0|M
@ &core/fseek
M = 0|D
@ &stdin.status
M = 0|D ; seek
; drop this whole stack frame
@ 012
D = 0|A
@ &macros/sp
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
@ &core/char
M = 0|D
@ :Macro_Expand_Resolve.
D = 0|A
@ &sym/next
M = 0|D
@ :Sym_Read.
= 0|D <=>

; Called after reading in the macro name.
  :Macro_Expand_Resolve.
@ :Macro_Expand_ResolveDone.
D = 0|A
@ &sym/next
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
@ &sym/value
D = 0|M
@ &macros/address
M = 0|D ; copy the resolved value into macro_address
@ &core/char
D = 0|M
@ :Macro_Expand_Call.
= 0|D = ; if char is \0, no arguments, call immediately
; there must be arguments, so start reading them with Val_Read
  :Macro_Expand_WithArguments.
@ &macros/sp
D = 0|M
@ &macros/argp
M = 0|D ; set argp to point at the start of the current macro stack frame
@ :Macro_Expand_ArgDone.
D = 0|A
@ &val/next
M = 0|D
@ :Val_Read.
= 0|D <=>

; We just finished reading in an argument, so store it in the next argv slot,
; increment argp, and either read another one or invoke the macro depending
; on whether we're at EOL or not.
  :Macro_Expand_ArgDone.
@ &val/value
D = 0|M
@ &macros/argp
A = 0|M
M = 0|D
@ &macros/argp
M = M+1
@ &core/char ; char = \0? end of line, so call the macro
D = 0|M
@ :Macro_Expand_Call.
= 0|D =
; otherwise look for another argument!
@ :Macro_Expand_ArgDone.
D = 0|A
@ &val/next
M = 0|D
@ :Val_Read.
= 0|D <=>

; Called to actually invoke the macro once we've read in the macro address and
; all the arguments, if any.
  :Macro_Expand_Call.
@ &macros/in-expansion
M = M+1
; Advance the macro stack pointer 11 words (10 arguments + return address)
@ 013
D = 0|A
@ &macros/sp
M = M+D
; push the current fseek onto the macro stack. The pointer points at the first
; empty slot, so we need to subtract 1 from it to get the right address.
@ &core/fseek
D = 0|M
@ &macros/sp
A = M-1
M = 0|D ; store current fseek at top of macro stack
; seek to the address of the macro definition
@ &macros/address
D = 0|M
@ &stdin.status
M = 0|D
@ &core/fseek
M = 0|D
; We jump back to mainloop here because the line containing the macroexpansion
; should be replaced with the first line of the macro, not with a no-op
; but this means that the state is still set to Sym_Read
; so instead we want to jump to NewInstruction to reset the state pointer, etc.
@ :NewInstruction.
= 0|D <=>
