;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 01-stack.asm
;; Stack manipulation macros. These are inspired by (but not the same as) the
;; ones in NANDgame.
;; SP is stored at $0. The stack itself starts at $100 and grows upwards.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

&SP = 0
; ARGS, LOCALS, and RETVAL are in 1, 2 and 3 for nandgame compatibility
&RSP = 4

; Initialize the stack.
; First argument is the base address of the data stack.
; Second is the base address of the call stack, which needs one word per nested
; function call.
[stack/init
  @ %0
  D = 0|A
  @ &SP
  M = 0|D
  @ %1
  D = 0|A
  @ &RSP
  M = 0|D
]

; pushd ( -- A )
; pushes the value of D onto the stack.
[pushd
  @ &SP    ; A holds SP address
  AM = M+1 ; increment stack pointer and get incremented ptr in A
  A = A-1  ; point A back to the slot we want to fill
  M = 0|D  ; store D
]

; pusha ( -- A )
; pushes the value of A onto the stack.
[pusha
  D = 0|A   ; save A
  ~pushd
]

; pushm ( -- M )
; pushes the value at the memory location currently pointed to by A onto the stack.
[pushm
  D = 0|M
  ~pushd
]

; pushconst,val ( -- const )
; pushes a literal or label value onto the stack.
[pushconst
  @ %0
  ~pusha
]

; pushvar,addr ( -- M )
; pushes the contents of a variable onto the stack. Equivalent to:
; ~pushconst,addr
; ~popa
; ~pushm
; but faster.
[pushvar
  @ %0
  D = 0|M
  ~pushd
]

; popa ( A -- )
; pops the value on top of the stack into A. Leaves D intact.
[popa
  @ &SP
  AM = M-1
  A = 0|M
]

; popd ( D -- )
; pops the value on top of the stack into D.
[popd
  @ &SP
  AM = M-1
  D = 0|M
]

; popm ( M -- )
; pops the value on top of the stack into the memory address currently pointed
; to by A.
; Fairly slow since we need to spill the address to RAM to make room for the
; data before reading the address back in.
[popm
  D = 0|A
  @ &SP
  A = 0|M
  M = 0|D ; store destination address atop the stack
  A = A-1
  D = 0|M ; read value into D
  A = A+1
  A = 0|M ; read address into A
  M = 0|D ; write value
  @ &SP
  M = M-1 ; decrement stack pointer
]

; popvar,addr ( M -- )
; pops the value on top of the stack into the named memory location.
[popvar
  ~popd
  @ %0
  M = 0|D
]

; dup ( x -- x x )
; duplicates the top value on the stack
; like popd pushd pushd, but faster
[dup
  @ &SP
  A = M-1
  D = 0|M ; get top of stack value into D
  @ &SP
  A = 0|M
  M = 0|D ; write to top of stack
  @ &SP
  M = M+1
]

; drop ( x -- )
; deletes the top value from the stack
[drop
  @ &SP
  M = M-1
]
