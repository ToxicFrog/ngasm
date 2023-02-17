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
; back to macro_origin when we hit the end.
:&in_macroexpansion.

; Offset in the input file where we hit the macro reference we're currently
; expanding.
:&macro_origin.

; these will require cooperation from the mainloop!

; on macro definition, we need to branch based on pass
; on first pass, we record the macro offset, then set macrodef flag
; on second pass, we set the macrodef flag until we see end of macro, which
; causes us to emit comments for everything

; on macro invokation, we need to:
; - record current file offset
; - seek to start of macro
; - set macroexpansion flag
; - compile as normal
; - at end of macro, unset macroexpansion flag and seek back to saved address
; on first pass this should give us the correct PC values, and on second pass
; it should emit the correct code


;[pushd
;  @ &pc
;  A = 0|M
;  M = 0|D
;  @ &pc
;  M = M+1
;]

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
; If we get this far we're in a macroexpansion. Clear the macroexpansion flag
; and seek back to the origin.
; Note that this does not call EndOfLine_Continue -- as far as the main loop
; is concerned, it read a ] which was ignored and then it read the rest of the
; line we seek back to.
@ :&in_macroexpansion.
M = 0&D
; fseek gets frozen when we're in a macroexpansion so we can use it here to
; reset to where the macro was called from -- specifically, the start of the
; line immediately after it was called.
@ :&fseek.
D = 0|M
@ 77760 ; &stdin_status
M = 0|D ; seek
@ :MainLoop.
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Macro_Expand
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by LineStart when it sees a macroexpansion.
  :Macro_Expand.
; Step one, resolve the macro. Pretend the first character is [ so that it matches
; the symbol seen at macro definition time.
@ 133 ; '['
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
; TODO: macro argument support -- check if &char is \0 (eol) or , and if the
; latter, after resolving, do a Val_Read and set that as the macro argument.
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
  :Macro_Expand_ResolveDone.
@ :&in_macroexpansion.
M = 0+1
@ :&sym_value.
D = 0|M
@ 77760 ; stdin_status
M = 0|D
; We jump back to mainloop here because the line containing the macroexpansion
; should be replaced with the first line of the macro, not with a no-op
; but this means that the state is still set to Sym_Read
; so instead we want to jump to NewInstruction to reset the state pointer, etc.
@ :NewInstruction.
= 0|D <=>
