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

; ~loadd,address
; Loads the value at address into D. Overwrites A.
[loadd
  @ %0
  D = 0|M
]

; ~stored,address
; Stores the value in D at the given address. Overwrites A.
[stored
  @ %0
  M = 0|D
]

; ~storec,value,address
; Stores a constant value at the given address. Overwrites both registers.
[storec
  @ %0
  D = 0|A
  ~stored, %1
]

; ~call,:function,nargs
; Calls the given function with the specified number of arguments on top of the
; stack. When it returns, the arguments have been popped and replaced with the
; (single) return value of the function.
; TODO: We're leaving a lot of optimization potential on the floor here -- in
; particular, if the function takes no args or has no locals we can skip
; saving/restoring those values, which is fairly expensive. Similarly, if the
; function returns nothing we don't need to save RETVAL in return and restore
; it in call. But those optimizations can wait until we have a more capable
; language to work in.
:__MACRO_CALL
[call
  ; Save old values of ARGS and LOCALS
  ~pushvar, &ARGS
  ~pushvar, &LOCALS
  ; set up new ARGS pointer as SP - 2 - nargs
  ~loadd, &SP
  @ 2
  D = D-A
  @ %1
  D = D-A
  ~stored, &ARGS
  ; push return address and jump to function
  ; +8 is the size of the pushconst macro (6) + the jmp macro (2)
  ~pushconst, +8
  ~jmp, %0
  ; at this point the function has just called ~return, which has left the
  ; return value in &RETVAL, and dropped all locals, leaving the saved LOCALS
  ; and ARGS from earlier on top of the stack.
  ; First, we restore those to their pre-call values:
  ~popvar, &LOCALS
  ~popvar, &ARGS
  ; Now we drop all the arguments from the stack; we could just set SP = ARGS,
  ; except that we no longer have the old version of ARGS, so instead we have
  ; to do math about it, knowing how many arguments we had:
  ~loadd, &SP
  @ %1
  D = D-A
  ~stored, &SP
  ; now push the return value and we're done!
  ~pushvar, &RETVAL
]

; ~function,nlocals
; Use as the first thing after a function label. Afterwards, &LOCALS will point
; to the start of the function's local vector and &SP will point just after it.
:__MACRO_FUNCTION
[function
  ; locals points to current SP
  ~loadd, &SP
  ~stored, &LOCALS
  ; advance SP by nlocals
  @ %0
  D = 0|A
  @ &SP
  M = M+D
]

; ~return
; Returns from the function by saving the return value, dropping its locals, and
; then popping and jumping to the saved return address.
:__MACRO_RETURN
[return
  ~popvar, &RETVAL
  ~loadd, &LOCALS
  ~stored, &SP
  ~popa
  = 0|D <=>
]

; ~loadnth,&ptr,n
; Given that &ptr is a variable holding a pointer to an array, loads the value
; in ptr[n] into both registers.
[loadnth
  @ %1 ; index in D
  D = 0|A
  @ %0 ; address of pointer in A
  A = M+D ; dereference to get array address and add index
  AD = 0|M
]

; ~loadarg,n ( -- )
; loads the given argument into the A and D registers
:__MACRO_LOADARG
[loadarg
  ~loadnth, &ARGS, %0
]

; ~loadlocal,n ( -- )
; loads the numbered local into the D and A registers
:__MACRO_LOADLOCAL
[loadlocal
  ~loadnth, &LOCALS, %0
]

; ~pusharg,n ( -- arg )
; pushes the nth argument (0-indexed) onto the stack.
:__MACRO_PUSHARG
[pusharg
  @ %0
  D = 0|A
  @ &ARGS
  A = A+D
  ~pushm
]

; ~pushlocal,n ( -- local )
; pushes the nth local (0-indexed) onto the stack
:__MACRO_PUSHLOCAL
[pushlocal
  @ %0
  D = 0|A
  @ &LOCALS
  A = 0|M
  A = A+D
  ~pushm
]

; ~poplocal,n ( local -- )
; pops a value from the stack and stores it in the nth local
:__MACRO_POPLOCAL
[poplocal
  ; first we compute the destination and temporarily store it atop the stack
  @ &LOCALS
  D = 0|M
  @ %0
  D = D+A ; D = LOCALS + n
  @ &SP
  A = 0|M ; A points to open slot
  M = 0|D ; store destination address
  ; get the actual value in D
  ~popd ; this leaves A pointing to the slot we just popped from
  ; get the address back
  A = A+1 ; point to the slot above that
  A = 0|M ; read address
  M = 0|D ; store D
]
