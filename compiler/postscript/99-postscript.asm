; If we somehow fall off the end of the program, jump to the end of ROM.
@ $7FFF
= 0|D <=>

; This both acts as a pointer into RAM used for the symbol table when compiling,
; and as a marker for the start of the symbol table in the generated compiler
; ROM, which is useful when debugging.
:&symbols.
