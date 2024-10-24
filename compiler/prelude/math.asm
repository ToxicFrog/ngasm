;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 03-math.asm
;; Simple math macros on the stack.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; add ( x y -- sum )
; Adds the top two values on the stack.
[add
  ~popd
  ~popa
  D = A+D
  ~pushd
]

; sub ( x y -- diff )
; Subtracts y from x.
[sub
  ~popd
  ~popa
  D = A-D
  ~pushd
]

; inctop ( x -- x' )
; Adds 1 to the top value on the stack.
[inctop
  @ &SP
  A = M-1
  M = M+1
]

; dectop ( x -- x' )
; Subtracts 1 from the top value on the stack.
[dectop
  @ &SP
  A = M-1
  M = M-1
]

; tobool ( x -- ? )
; convert top of stack to boolean; 0=0, anything else =1
[tobool
  @ &SP
  A = M-1
  D = 0|M
  @ +3
  = 0|D = ; skip next bit if D=0
  D = 0+1 ; D was nonzero, normalize to 1
  @ &SP
  A = M-1
  M = 0|D
]

; not ( x -- !x )
; swap boolean between 0 and 1. UB on values other than 0/1.
[not
  D = 0+1
  @ &SP
  A = M-1
  M = D-M
]

; neq ( x y -- ? )
; pushes 0 if x and y are equal, 1 otherwise
[neq
  ~sub
  ~tobool
]

; eq ( x y -- ? )
; pops two values, pushes 1 if they are equal and 0 otherwise
[eq
  ~neq
  ~not
]
