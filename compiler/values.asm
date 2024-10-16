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
&val/value = $40

; The continuation to call once the value is read.
&val/next = $41

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Val_Read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  :Val_Read
; Clear the value buffer.
@ &val/value
M = 0&D
; Update state pointer
~storec, :Val_Read_State, &core/state
; This is called when we know the next token is going to be a value, so we just
; return control to the mainloop. Val_Read_State will transfer control to
; subsidiary states as needed.
~jmp, :MainLoop

; This is the master value-reading state. It will transfer control to a secondary
; state based on the first character sees; a :, &, or # means a symbol reference
; which must be resolved, a ' means a character constant, a $ means a hexadecimal
; constant, a 0 means an octal constant, ~ and % mean macro expansion and
; argument splicing, and anything else we optimistically assume is a decimal constant.
  :Val_Read_State
; First, check for ':', '&', and '#'. These all immediately transfer control to
; Sym_Read, so we set up the continuation for those ahead of time.
~storec, :Val_Read_SymDone, &sym/next
; Now check the actual characters
~loadd, &core/char
~jeq, \:, :Sym_Read
~loadd, &core/char
~jeq, \#, :Sym_Read
~loadd, &core/char
~jeq, \&, :Sym_Read
; Now check for a character constant.
~loadd, &core/char
~jeq, \\, :Val_Read_Char
; Relative jump address backwards?
~loadd, &core/char
~jeq, \-, :Val_Read_RelativeJump_Back
; Relative jump address forwards?
~loadd, &core/char
~jeq, \+, :Val_Read_RelativeJump_Forward
; Hex constant starting with $?
~loadd, &core/char
~jeq, \$, :Val_Read_Hex
; Octal constant starting with 0?
~loadd, &core/char
~jeq, \0, :Val_Read_Oct
; Macroexpansion argument?
~loadd, &core/char
~jeq, \%, :Val_Read_MacroArg
; None of the above? Assume it's a decimal constant. Set that as the current
; state and then jump to it to process the first character.
~storec, :Val_Read_Dec, &core/state
~jmp, :Val_Read_Dec


; Called after reading in a symbol. We need to call Sym_Resolve to get the
; associated value.
  :Val_Read_SymDone
~storec, :Val_Read_SymResolved, &sym/next
~jmp, :Sym_Resolve

; Sym_Resolve is finished so copy the value it resolved into value and return
; control to our caller.
  :Val_Read_SymResolved
~loadd, &sym/value
~stored, &val/value
@ &val/next
A = 0|M
= 0|D <=>

; The state for reading a character constant. Character constants have the
; format \x and scan as the character code for x, so (e.g.) \a is 97.
  :Val_Read_Char
; Set ourself as the current state first
@ :Val_Read_Char
D = 0|A
@ &core/state
M = 0+D
; If char is 0 we're at EOL and have nothing further to do
~loadd, &core/char
@ &val/next
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
~loadd, &core/char
@ $2C
D = D-A
@ &val/next
A = 0|M
= 0|D =
; Otherwise just copy char into the value buffer
~loadd, &core/char
~stored, &val/value
~jmp, :MainLoop

; These are for generating relative jump values. It is the same as decimal
; values except at the end, we must add or subtract it from the program counter.
; So we delegate this to Val_Read_Dec except we also set a flag indicating that
; at the end of reading the value it should apply the PC offset.
; So here's the flag:
  :&relative-jump-mode.
; And the procedures:
  :Val_Read_RelativeJump_Back
@ :&relative-jump-mode.
M = 0-1
@ :Val_Read_Dec_State
D = 0|A
@ &core/state
M = 0+D
~jmp, :MainLoop

  :Val_Read_RelativeJump_Forward
@ :&relative-jump-mode.
M = 0+1
@ :Val_Read_Dec_State
D = 0|A
@ &core/state
M = 0+D
~jmp, :MainLoop

; Called to read a macro argument. Read one decimal digit and return
; *(*macro_sp - 11 + digit).
  :Val_Read_MacroArg
@ :Val_Read_MacroArg_State
D = 0|A
@ &core/state
M = 0+D
~jmp, :MainLoop

  :Val_Read_MacroArg_State
; if at end of line, call the continuation
~loadd, &core/char
@ &val/next
A = 0|M
= 0|D =
; are we in macroexpansion? then we want MacroArg_Expansion below
~loadd, &macros/in-expansion
@ :Val_Read_MacroArg_Expansion
= 0|D <>
; otherwise we're in macro definition and just emit a placeholder value
; this is a behaviour difference from stage 4, which emitted uninitialized
; memory instead
~storec, 0, &val/value
~jmp, :Val_Read_MacroArg_Done
  :Val_Read_MacroArg_Expansion
; read the argument off the macroexpansion stack and store it into value
~loadd, &core/char
@ 060 ; '0'
D = D-A ; D contains the digit now, 0-9
@ 013
D = D-A ; subtract 11
@ &macros/sp
A = 0|M ; read current macro stack pointer
A = A+D ; add our offset, which is now between -11 and -2
D = 0|M ; dereference to read the value into D, then store it in value
~stored, &val/value
  :Val_Read_MacroArg_Done
; and then return to the main loop
~jmp, :MainLoop

; Called by LoadImmediate on encountering the leading $ of a hex constant.
; Unlike DecimalConstant we don't want to ingest the first character of the
; constant (since $ is not a digit), so we just set ReadDigit as the current
; state and return to the main loop, which will start feeding it characters
; starting with the *next* character.
  :Val_Read_Hex
@ :Val_Read_Hex_State
D = 0|A
@ &core/state
M = 0+D
~jmp, :MainLoop

; The state for reading a hex constant. This is equivalent to a decimal constant
; except that (a) we multiply by 16 instead of by 10 each digit and (b) we understand
; the digits A-F and a-f as corresponding to the values 10-15.
  :Val_Read_Hex_State
; Check if we're at end of line, if so just do nothing
~loadd, &core/char
@ &val/next
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
~loadd, &core/char
@ 054 ; ','
D = D-A
@ &val/next
A = 0|M
= 0|D =
; Start by making room in the value buffer
~loadd, &val/value
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
~loadd, &core/char
@ 0141 ; 'a'
D = D-A
@ :Val_Read_HexLower
= 0|D >=
~loadd, &core/char
@ 0101 ; 'A'
D = D-A
@ :Val_Read_HexUpper
= 0|D >=
~jmp, :Val_Read_HexNumeric

  :. ; for some reason we need a dummy label here or the definition of the
  ; following label doesn't stick.
  :Val_Read_HexLower
~loadd, &core/char
@ 0127 ; 'a' - 10
D = D-A
@ &val/value
M = D+M
~jmp, :MainLoop

  :Val_Read_HexUpper
~loadd, &core/char
@ 067 ; 'A' - 10
D = D-A
@ &val/value
M = D+M
~jmp, :MainLoop

  :Val_Read_HexNumeric
~loadd, &core/char
@ 060 ; '0'
D = D-A
@ &val/value
M = D+M
~jmp, :MainLoop

; The state for reading the number in a load immediate instruction.
; The number is decimal, so for each digit, we multiply the existing number by
; 10 by repeated addition, then add the new digit to it.
  :Val_Read_Dec
@ :Val_Read_Dec_State
D = 0|A
@ &core/state
M = 0+D
; fall through to state

  :Val_Read_Dec_State
; Check if we're at end of line. If so we may need to do processing for relative
; jumps before we generate the opcode, and in either case we should then call
; the val_next continuation.
~loadd, &core/char
~jz, :Val_Read_Dec_EOL
; If char is , this is an argument separator, same deal as EOL
~loadd, &core/char
~jeq, $2C, :Val_Read_Dec_EOL  ; 2C is \,
; Start by making room in the value buffer
~loadd, &val/value
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
~loadd, &core/char
; Subtract '0' to get a value in the range 0-9
; or out of the range if the user typed in some sort of garbage, oh well
@ 060 ; '0'
D = D-A
@ &val/value
M = D+M
~jmp, :MainLoop

  :Val_Read_Dec_EOL
~loadd, :&relative-jump-mode.
M = 0&D ; clear the flag, we have the value saved in D
@ :Val_Read_Dec_JumpBack
= 0|D <
@ :Val_Read_Dec_JumpForward
= 0|D >
~jmp, :Val_Read_Dec_Done

  :Val_Read_Dec_JumpBack
~loadd, &core/pc
@ &val/value
M = D-M
~jmp, :Val_Read_Dec_Done

  :Val_Read_Dec_JumpForward
~loadd, &core/pc
@ &val/value
M = D+M
~jmp, :Val_Read_Dec_Done

  :Val_Read_Dec_Done
; call the continuation
@ &val/next
A = 0|M
= 0|D <=>

; The state for reading the number in a load immediate instruction.
; This is the reader for octal numbers, which we're probably going to remove
; but stays here for backwards compatibility.
  :Val_Read_Oct
@ :Val_Read_Oct_State
D = 0|A
@ &core/state
M = 0+D
; fall through to state

  :Val_Read_Oct_State
; Check if we're at end of line, if so just do nothing
~loadd, &core/char
@ &val/next
A = 0|M
= 0|D =
; If char is , this is an argument separator, same deal as EOL
~loadd, &core/char
@ 054 ; ','
D = D-A
@ &val/next
A = 0|M
= 0|D =
; Start by making room in the value buffer
~loadd, &val/value
; Add D to M 7 times for a total of x8
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
M = D+M
; Now add the next digit
~loadd, &core/char
; Subtract '0' to get a value in the range 0-7
; or out of the range if the user typed in some sort of garbage, oh well
@ 060 ; '0'
D = D-A
@ &val/value
M = D+M
~jmp, :MainLoop
