@ $4F03
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 03-math.asm
;; Simple math macros on the stack.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; add ( x y -- sum )
; Adds the top two values on the stack.
[add
  ~popd
  ~popa
  A = A+D
  ~pusha
]

; sub ( x y -- diff )
; Subtracts y from x.
[sub
  ~popd
  ~popa
  A = A-D
  ~pusha
]

; inc ( x -- x' )
; Adds 1 to the top value on the stack.
[inc
  ~popa
  A = A+1
  ~pusha
]

; dec ( x -- x' )
; Subtracts 1 from the top value on the stack.
[dec
  ~popa
  A = A-1
  ~pusha
]
