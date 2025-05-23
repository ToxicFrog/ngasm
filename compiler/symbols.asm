;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; symbols.asm
;; Code for the symbol table:
;; - parsing symbols from input
;; - binding symbols to values
;; - resolving symbols
;; This will be used for labels, constants, and macros.
;;
;; It exports three procedures:
;; - Sym_Read, which activates a parser state for reading a symbol
;; - Sym_Bind, which creates a new entry in the symbol table
;; - Sym_Resolve, which looks up a symbol table entry
;; And three variables: &symbol, &sym_value, and &sym_next.
;; See the comments below for details on how to use these.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Public Variables ;;;;

; Contains the hash of the current symbol. Read fills this in; Bind and
; Resolve both read it.
&sym/name = $20

; Contains the value associated with a symbol. Bind reads it to get the symbol's
; value when creating a new binding, Resolve
&sym/value = $21

; Continuation. Since Read, Bind, and Resolve all get called by multiple places
; in the parser, and we don't actually have functions or, really, a stack at all
; yet, it is assumed that the caller will drop the address of the next procedure
; to call into this variable. Once one of these utility functions/states is done
; (for Bind/Resolve, when they complete, and for Read, once it reaches the end of
; the symbol input), it will *immediately* jump to whatever address this points
; to.
; Although note that on symbol resolution failure it will instead jump to Error.
&sym/next = $22

;;;; Private Variables ;;;;
; These are internal workings of the symbol table; do not touch!

; Pointer just past the end of the symbol table. To write a new symbol we put
; it here and then increment this pointer. When resolving a symbol, if we reach
; this point, we've gone too far.
&sym/last = $23

; The actual table. The table is an array of [symbol_hash, value] pairs
; occupying two words each and stored contiguously in memory.
; This goes last since it will grow as new symbols are added and we don't want
; it overwriting one of our other vars!
;:&symbols.
; This turns out not to be large enough, so it gets shoved to zz-postscript
; instead.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Read                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; This is responsible for reading a symbol from input and leaving its hash in
; sym/name. At the end of reading it calls sym/next; whatever code that points
; to is responsible for doing something with the hash, probably either calling
; Bind or Resolve.
;
; Callers are expected to call it directly; it will update the state pointer
; itself. This allows it to set up internal structures it needs correctly.
  :Sym_Read
; Clear the symbol hash
@ &sym/name
M = 0&D
; Update state pointer
~storec, :Sym_Read_State, &core/state
; fall through to Sym_Read_State

; This is the actual state. It receives each individual character.
; First, if we're at the end of the symbol -- EOL or the '=' or ',' characters --
; it should jump to sym_next.
; Note that it doesn't go straight to EndOfLine_Continue at end of line -- the
; *caller* is responsible for that!
  :Sym_Read_State
; check for end of line
~loadd, &core/char
@ &sym/next
A = 0|M
= 0|D =
; check for comma and equals
~loadd, &core/char
@ 054 ; ','
D = D-A
@ &sym/next
A = 0|M
= 0|D =
; check for end of line
~loadd, &core/char
@ 075 ; '='
D = D-A
@ &sym/next
A = 0|M
= 0|D =
; Not at end, so add the just-read character to the label hash.
; First, double the existing hash to shift left 1 bit.
~loadd, &sym/name
D = D+M
; Then add the new character to it.
@ &core/char
D = D+M
~stored, &sym/name
; return to main loop
~jmp, :MainLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Bind                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by the first-pass compiler to bind symbols to values. It expects the
; symbol hash in symbol and the associated value in sym_value.
; Note that no error checking is performed; in particular there is nothing to
; stop you from re-using a variable name, and if you do, only one of the bindings
; will take effect FOR THE ENTIRE PROGRAM.
;
; This is not a parser state; you call it and it does its work and then immediately
; calls *sym_next.
  :Sym_Bind ; ( value nameid -- nil )
~function
  ; last_sym should already be pointing to the free slot at the end of the symbol
  ; table, so write the nameid to it
  ~popd
  @ &sym/last
  A = 0|M
  M = 0|D ; *last_sym = D
  ; increment last_sym so it points to the value slot
  @ &sym/last
  M = M+1
  ; write the value we were given to that slot
  ~popd
  @ &sym/last
  A = 0|M
  M = 0|D
  ; increment last_sym again so it points to the next, unused slot
  @ &sym/last
  M = M+1
~return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Resolve                                                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by the second-pass compiler (and once we have macros, the first-pass as
; well) when resolving a symbol. It expects the symbol nameid as its first and
; only argument, and returns the associated value.
; If the symbol cannot be resolved it jumps to Error.
  :Sym_Resolve ; ( nameid -- value )
~function
  ~pushconst, :&symbols. ; pointer for scanning symbol table

    :Sym_Resolve_Loop
  ; Check if we're at the end of the symbol table, and abort if so.
  ~dup
  ~pushvar, &sym/last
  ~eq
  ~popd
  ~jnz, :Sym_Resolve_Error
  ; Check if the current symbol is the one we're looking for.
  ~dup
  ~deref ; get the nameid in the current slot
  ~dupnth, 2 ; get the nameid we're looking for
  ~eq
  ~popd
  ~jnz, :Sym_Resolve_Success
  ; It wasn't :( advance the pointer to the next entry and retry.
  ~inctop
  ~inctop
  ~jmp, :Sym_Resolve_Loop

  ; Called when we successfully find an entry in the symbol table.
  ; Top of the stack holds the pointer to the nameid field of the correct slot.
    :Sym_Resolve_Success
  ~inctop
  ~deref
  ~nip
  ~return

  ; Called when we cannot find the requested symbol in the table.
  ; On pass 0 we may have just not seen the symbol definition yet, so instead we
  ; return 0.
  ; On pass 1, we error out.
    :Sym_Resolve_Error
  ~drop
  ~loadd, &core/pass
  ~jnz, :Error
~return

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Dump                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called at the end of the program, after successfully writing a ROM image.
; Dumps the symbol table to stdout in a debugger-friendly format.
  :Sym_Dump ; ( -- )
~function
  ~pushconst, :&symbols.

    :Sym_Dump_Iter
  ; this_sym == last_sym? break
  ~dup
  ~pushvar, &sym/last
  ~eq
  ~popd
  ~jnz, :Sym_Dump_Done
  ; else dump next table entry and increment this_sym
  ~dup
  ~deref
  ~popvar, &stdout.words
  ~inctop
  ~dup
  ~deref
  ~popvar, &stdout.words
  ~inctop
  ~jmp, :Sym_Dump_Iter
    :Sym_Dump_Done
  ; write total symbol count and then exit program
  @ :&symbols.
  D = 0|A
  @ &sym/last
  D = M-D
  @ &stdout.words
  M = 0|D
~return
