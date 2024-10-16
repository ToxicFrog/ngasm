;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 01-flowcontrol.asm
;; Flow control macros (i.e. jumps).
;; These are tailored to what the compiler needs; they aren't meant to cover
;; every eventuality.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ~jmp,address
; Unconditional jump to the given address. Overwrites A.
[jmp
  @ %0
  = 0|D <=>
]

; ~jeq,const,address
; Jump if D is equal to the given const. Overwrites A and D.
[jeq
  @ %0
  D = D-A
  @ %1
  = 0|D =
]

; ~jz,address
; Jump if D is zero. Usually part of a sequence like:
; ~loadd,&variable
; ~jz,:Label
[jz
  @ %0
  = 0|D =
]

