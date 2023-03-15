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
; constant, and anything else we optimistically assume is a decimal constant.
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
@ 72 ; ':'
D = D-A
@ :Sym_Read.
= 0|D =
@ :&char.
D = 0|M
@ 43 ; '#'
D = D-A
@ :Sym_Read.
= 0|D =
@ :&char.
D = 0|M
@ 46 ; '&'
D = D-A
@ :Sym_Read.
= 0|D =
; Now check for a character constant.
@ :&char.
D = 0|M
@ 47 ; "'"
D = D-A
@ :Val_Read_Char.
= 0|D =
; Relative jump address backwards?
@ :&char.
D = 0|M
@ 55 ; '-'
D = D-A
@ :Val_Read_RelativeJump_Back.
= 0|D =
; Relative jump address forwards?
@ :&char.
D = 0|M
@ 53 ; '+'
D = D-A
@ :Val_Read_RelativeJump_Forward.
= 0|D =
; Hex constant starting with $?
@ :&char.
D = 0|M
@ 44 ; '$'
D = D-A
@ :Val_Read_Hex.
= 0|D =
; Macroexpansion argument?
@ :&char.
D = 0|M
@ 45 ; '%'
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
@ 54 ; ','
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
; *(macro_argv + digit).
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
@ 60 ; '0'
D = D-A
@ :&macro_argv.
A = A+D
D = 0|M
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
@ 54 ; ','
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
@ 141 ; 'a'
D = D-A
@ :Val_Read_HexLower.
= 0|D >=
@ :&char.
D = 0|M
@ 101 ; 'A'
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
@ 127 ; 'a' - 10
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

  :Val_Read_HexUpper.
@ :&char.
D = 0|M
@ 67 ; 'A' - 10
D = D-A
@ :&value.
M = D+M
@ :MainLoop.
= 0|D <=>

  :Val_Read_HexNumeric.
@ :&char.
D = 0|M
@ 60 ; '0'
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
@ 54 ; ','
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
@ 60 ; '0'
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

