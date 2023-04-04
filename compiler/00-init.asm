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


; Memory-mapped IO we still need to hard-code until we have define, using labels
; as variables only works for stuff where we don't care exactly where it ends up.

; Entry point
@ :Init.
= 0+D <=>
