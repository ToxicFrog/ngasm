;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; symbols.asm
;; Code for the symbol table:
;; - parsing symbols from input
;; - binding symbols to values
;; - resolving symbols
;; This will be used for labels, constants, and macros.
;;
;; This exposes one parser state (Sym_Read), two procedures (Sym_Bind and
;; Sym_Resolve), and three variables (&symbol, &sym_value, and &sym_next).
;; See below for details on how to use them.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;; Public Variables ;;;;

; Contains the hash of the current symbol. Read fills this in; Bind and
; Resolve both read it.
:&symbol.

; Contains the value associated with a symbol. Bind reads it to get the symbol's
; value when creating a new binding, Resolve
:&sym_value.

; Continuation. Since Read, Bind, and Resolve all get called by multiple places
; in the parser, and we don't actually have functions or, really, a stack at all
; yet, it is assumed that the caller will drop the address of the next procedure
; to call into this variable. Once one of these utility functions/states is done
; (for Bind/Resolve, when they complete, and for Read, once it reaches the end of
; the symbol input), it will *immediately* jump to whatever address this points
; to.
; Although note that on symbol resolution failure it will instead jump to Error.
:&sym_next.

;;;; Private Variables ;;;;
; These are internal workings of the symbol table; do not touch!

; Pointer just past the end of the symbol table. To write a new symbol we put
; it here and then increment this pointer. When resolving a symbol, if we reach
; this point, we've gone too far.
:&last_sym.

; Pointer to the current symbol we are looking at. Used during symbol resolution
; as scratch space.
:&this_sym.

; The actual table. The table is an array of [symbol_hash, value] pairs
; occupying two words each and stored contiguously in memory.
; This goes last since it will grow as new symbols are added and we don't want
; it overwriting one of our other vars!
:&symbols.

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
  :Sym_Read.
; Clear the symbol hash
@ :&symbol.
M = 0&D
; Update state pointer
@ :Sym_Read_State.
D = 0|A
@ :&state.
M = 0|D
; fall through to Sym_Read_State

; This is the actual state. It receives each individual character.
; First, if we're at the end of the symbol -- EOL or the '=' or ',' characters --
; it should jump to sym_next.
; Note that it doesn't go straight to EndOfLine_Continue at end of line -- the
; *caller* is responsible for that!
  :Sym_Read_State.
; check for end of line
@ :&char.
D = 0|M
@ :&sym_next.
A = 0|M
= 0|D =
; check for comma and equals
@ :&char.
D = 0|M
@ 54 ; ','
D = D-A
@ :&sym_next.
A = 0|M
= 0|D =
; check for end of line
@ :&char.
D = 0|M
@ 75 ; '='
D = D-A
@ :&sym_next.
A = 0|M
= 0|D =
; Not at end, so add the just-read character to the label hash.
; First, double the existing hash to shift left 1 bit.
@ :&symbol.
D = 0|M
D = D+M
; Then add the new character to it.
@ :&char.
D = D+M
@ :&symbol.
M = 0|D
; return to main loop
@ :MainLoop.
= 0|D <=>

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
  :Sym_Bind.
; last_sym should already be pointing to the free slot at the end of the symbol
; table, so write the hash to it
@ :&symbol.
D = 0|M ; D = symbol
@ :&last_sym.
A = 0|M
M = 0|D ; *last_sym = D
; increment last_sym so it points to the value slot
@ :&last_sym.
M = M+1
; write the value we were given to that slot
@ :&sym_value.
D = 0|M
@ :&last_sym.
A = 0|M
M = 0|D
; increment last_sym again so it points to the next, unused slot
@ :&last_sym.
M = M+1
; call sym_next
@ :&sym_next.
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
  :Sym_Resolve.
; Startup code - set this_sym = &symbols
@ :&symbols.
D = 0|A
@ :&this_sym.
M = 0|D
  :Sym_Resolve_Loop.
; Are we at the end of the symbol table? If so, error out.
@ :&last_sym.
D = 0|M
@ :&this_sym.
D = D-M
@ :Error.
= 0|D =
; Check if the current symbol is the one we're looking for.
@ :&this_sym.
A = 0|M ; fixed?
D = 0|M
@ :&symbol.
D = D-M
@ :Sym_Resolve_Success.
= 0|D =
; It wasn't :( Advance this_sym by two to point to the next entry, and loop.
@ :&this_sym.
M = M+1
M = M+1
@ :Sym_Resolve_Loop.
= 0|D <=>

; Called when we successfully find an entry in the symbol table. this_sym holds
; a pointer to the label cell of the entry, so we need to inc it to get the
; value cell.
  :Sym_Resolve_Success.
@ :&this_sym.
A = M+1
D = 0|M
; now write the value into &sym_value so the caller can fetch it
@ :&sym_value.
M = 0|D
; return control to the caller
@ :&sym_next.
A = 0|M
= 0|D <=>
