;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ~call,:function
; Calls a function. The caller should push arguments, if any, onto the stack,
; and expect return values (again, if any) on the stack afterwards.
:__MACRO_CALL
[call
  @ +7
  D = 0|A
  @ &RSP
  AM = M+1
  M = 0|D
  @ %0
  = 0|D <=>
]

; ~function
; Use as the first thing after a function label. Currently does nothing, might
; do some sort of function prelude later.
:__MACRO_FUNCTION
[function
]

; ~return
; Returns from a function by popping the return address from RSP.
:__MACRO_RETURN
[return
  @ &RSP
  AM = M-1
  A = A+1
  A = 0|M
  = 0|D <=>
]

; ~loadstack,n ( -- )
; loads the given stack element, numbered 0-indexed from the top, into A and D
:__MACRO_LOADSTACK
[loadstack
  @ %0
  D = A+1
  @ &SP
  A = M-D
  AD = 0|M
]

; ~dupnth,n ( -- x )
; duplicate the nth element on the stack. ~dup is an optimized version of
; ~dupnth,0.
[dupnth
  ~loadstack, %0
  ~pushd
]
