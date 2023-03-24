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
