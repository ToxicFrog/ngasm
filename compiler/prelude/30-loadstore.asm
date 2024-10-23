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

; ~storea,address
; Stores the value in A at the given address. Overwrites A and D.
[storea
  D = 0|A
  ~stored, %0
]

; ~storec,value,address
; Stores a constant value at the given address. Overwrites both registers.
[storec
  @ %0
  D = 0|A
  ~stored, %1
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

