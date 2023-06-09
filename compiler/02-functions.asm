;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 02-functions.asm
;; call/return and function definitions.
;; This mimics the nandgame abi; see abi.md for details.
;; The short form is:
;; - caller pushes arguments and then calls ~call,:fn,nargs; :fn is called and
;;   the arguments are popped and return value is left on the stack
;; - function starts with ~function,nlocals macro
;; - in function body, &LOCALS points to first local, &ARGS to first arg; or
;;   use pusharg/pushlocal macros
;; - to return a value just push it and then call ~return
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

&ARGS = 1
&LOCALS = 2
&RETVAL = 3

; ~call,:function,nargs
; Calls the given function with the specified number of arguments on top of the
; stack. When it returns, the arguments have been popped and replaced with the
; (single) return value of the function.
[call
  ; Save old values of ARGS and LOCALS
  ~pushvar,&ARGS
  ~pushvar,&LOCALS
  ; set up new ARGS pointer
  @ &SP
  D = 0|M
  @ 2
  D = D-A
  @ %1
  D = D-A
  @ &ARGS
  M = 0|D
  ; push return address and jump to function
  ~pushconst,+2
  @ %0
  = 0|D <=>
  ; at this point the function has just called ~return, which has left the
  ; return value in &RETVAL and &SP pointing somewhere into the stack frame.
  ; First, drop the rest of the frame from the stack by jumping SP back to the
  ; saved value of ARGS.
  @ &ARGS
  D = 0|M
  @ &SP
  M = 0|D
  ; now push the return value and we're done!
  ~pushvar,&RETVAL
]

; ~function,nlocals
; Use as the first thing after a function label. Afterwards, &LOCALS will point
; to the start of the function's local vector and &SP will point just after it.
[function
  ; locals points to current SP
  @ &SP
  D = 0|M
  @ &LOCALS
  M = 0|D
  ; advance SP by nlocals
  @ %0
  D = 0|A
  @ &SP
  M = M+D
]

; ~return
; Returns from the function by saving the return value, dropping its locals, and
; then popping and jumping to the saved return address.
[return
  ~popvar,&RETVAL
  @ &LOCALS
  D = 0|M
  @ &SP
  M = 0|D
  ~popa
  = 0|D <=>
]

; ~pusharg,n ( -- arg )
; pushes the nth argument (0-indexed) onto the stack.
[pusharg
  @ %0
  D = 0|A
  @ &ARGS
  A = A+D
  ~pushm
]

; ~pushlocal,n ( -- local )
; pushes the nth local (0-indexed) onto the stack
[pushlocal
  @ %0
  D = 0|A
  @ &LOCALS
  A = A+D
  ~pushm
]
