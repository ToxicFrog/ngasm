;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 00-init.asm
;; Program entry point.
;; The name starts with 0_ so that when concatenating the various asm files
;; to get the input to the assembler, this comes first.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Unconditionally jump to the actual entrypoint.
; This lets us put whatever other code between here and Init that we want.
@ :Init
= 0|D <=>
