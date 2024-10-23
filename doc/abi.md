# New ABI

This document describes the ABI used for the compiler since version 5 (when
proper function calls were introduced). For the NANDGame API, see
[nandgame-api.md](./nandgame-api.md).

This is a simpler API than the NANDGame one, and a faster one. It is inspired
by stack languages like Forth and Factor.

## Glossary

- *caller*: the function using the `CALL` macro
- *callee*: the function being called
- *preamble*: code in CALL that runs before it jumps to the function it's calling,
              or code in FUNCTION that runs before the function itself does
- *postscript*: code in CALL that runs after the function it's calling returns
- *data stack*: the stack used for function arguments, return values, and temporaries
- *call stack*: the stack used for storing function return addresses

## ABI for Programmers

If you aren't actually *writing* call/return and just want to write functions,
here is the interface.

### Caller

Push all arguments onto the data stack, probably using the `~push*` macros,
then invoke the function with `~call, :FunctionName`. Once it returns, control
will resume at the instruction following the call. The stack protocol is
freeform; the callee is free to do whatever it wants to the stack, but ideally,
when it returns, the arguments will have been popped from the stack and the
return values, if any, pushed.

### Callee

Declare a function with:
```
:FunctionName
~function
  ; function body goes here
~return
```

When the function begins executing, the data stack is in the same state it was
in when the caller `~call`ed it. It is the responsibility of the function to
do whatever is needed to the stack; in particular, it is untidy to leave arguments
lying around for the caller to clean up if they are no longer needed. You can
easily access the top 10 elements of the stack using the `~loadstack` macro.

When done, you should push the return values, if any, then use `~return`.

## ABI Internals Overview

The ABI makes use of two globals: `&SP`, the data stack pointer, and `&RSP`, the
return stack pointer. There are no separate globals for locals or arguments.

This makes it a lot simpler than the NANDGame ABI, with no separate stack frames
or specific stack protocol. `~call` simply increments `&RSP` and then stores the
return address through it. `~return` reads the return address through `&RSP`,
decrements `&RSP`, and then jumps to it. The function preamble, `~function`,
doesn't currently do anything, although it might in the future be extended
to support some sort of debugging info or similar.
