;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 01-stack.asm
;; Stack manipulation macros. These are inspired by (but not the same as) the
;; ones in NANDgame.
;; SP is stored at $0. The stack itself starts at $100 and grows upwards.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

&SP = 0

; pushd ( -- A )
; pushes the value of D onto the stack.
[pushd
  @ &SP
  A = 0|M
  M = 0|D
  @ &SP
  M = M+1
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
  M = M-1
  A = 0|M
]

; popd ( D -- )
; pops the value on top of the stack into D.
[popd
  @ &SP
  M = M-1
  D = 0|M
]

; popm ( M -- )
; pops the value on top of the stack into the memory address currently pointed
; to by A.
; How do I implement this? I can save A into D and then use A to decrement SP,
; at which point D contains the address we want to store to and *SP is the
; value we want to store, but we need to end up with the value in D and the
; address in A. I may need to temporarily hijack the top of the stack.

; popvar,addr ( M -- )
; pops the value on top of the stack into the named memory location.
[popvar
  ~popd
  @ %0
  M = 0|D
]

; dup ( x -- x x )
; duplicates the top value on the stack
[dup
  ~popd
  ~pushd
  ~pushd
]

; drop ( x -- )
; deletes the top value from the stack
[drop
  @ &SP
  M = M-1
]
