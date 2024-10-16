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

; Pointer to the current symbol we are looking at. Used during symbol resolution
; as scratch space.
&sym/this = $24

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
; symbol. At the end of reading it calls sym_next; whatever code that points
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
  :Sym_Bind
; last_sym should already be pointing to the free slot at the end of the symbol
; table, so write the hash to it
~loadd, &sym/name ; D = symbol
@ &sym/last
A = 0|M
M = 0|D ; *last_sym = D
; increment last_sym so it points to the value slot
@ &sym/last
M = M+1
; write the value we were given to that slot
~loadd, &sym/value
@ &sym/last
A = 0|M
M = 0|D
; increment last_sym again so it points to the next, unused slot
@ &sym/last
M = M+1
; call sym_next
@ &sym/next
A = 0|M
= 0|D <=>

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Resolve                                                                ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called by the second-pass compiler (and once we have macros, the first-pass as
; well) when resolving a symbol. It expects the symbol hash in *symbol and will
; leave the value in *sym_value. If the symbol cannot be resolved it jumps to Error.
;
; Like Sym_Bind it is not a state; you call it and it does its work immediately
; and then calls sym_next.
;
; A common pattern is going to be something like:
;   :MyState
;   [if we are reading a symbol:]
;   [put MyState_Resolve in sym_next]
;   @ :Sym_Read
;   JMP
;   :MyState_Resolve
;   [put MyState_ResolveDone in sym_next]
;   @ :Sym_Resolve
;   JMP
;   :MyState_ResolveDone
;   [code to do something with the resolved value]
  :Sym_Resolve
; Startup code - set this_sym = &symbols
~storec, :&symbols., &sym/this
  :Sym_Resolve_Loop
; Are we at the end of the symbol table? If so, error out.
~loadd, &sym/last
@ &sym/this
D = D-M
~jz, :Sym_Resolve_Error
; Check if the current symbol is the one we're looking for.
@ &sym/this
A = 0|M ; fixed?
D = 0|M
@ &sym/name
D = D-M
~jz, :Sym_Resolve_Success
; It wasn't :( Advance this_sym by two to point to the next entry, and loop.
@ &sym/this
M = M+1
M = M+1
~jmp, :Sym_Resolve_Loop

; Called when we successfully find an entry in the symbol table. this_sym holds
; a pointer to the label cell of the entry, so we need to inc it to get the
; value cell.
  :Sym_Resolve_Success
@ &sym/this
A = M+1
D = 0|M
; now write the value into &sym_value so the caller can fetch it
~stored, &sym/value
; return control to the caller
@ &sym/next
A = 0|M
= 0|D <=>

; Called when we cannot find the requested symbol in the table.
; On pass 1 we may have just not seen the symbol definition yet, so instead we
; return whatever is currently in sym_value.
; On pass 2, we error out.
  :Sym_Resolve_Error
~loadd, &core/pass
@ &sym/next
A = 0|M
= 0|D =
; pass != 0, raise an error.
~jmp, :Error

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Sym_Dump                                                                   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Called at the end of the program, after successfully writing a ROM image.
; Dumps the symbol table to stdout in a debugger-friendly format.
  :Sym_Dump
~function, 0
~storec, :&symbols., &sym/this
  :Sym_Dump_Iter
; this_sym == last_sym? break
~loadd, &sym/this
@ &sym/last
D = D-M
~jz, :Sym_Dump_Done
; else dump next table entry and increment this_sym
@ &sym/this
A = 0|M
D = 0|M
@ &stdout.words
M = 0|D
@ &sym/this
M = M+1
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
