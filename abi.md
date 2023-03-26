# NANDgame ABI

This document describes the Application Binary Interface for NANDgame, the low-level
details of how function calls and returns work. This is documented in-game in the
levels `CALL`, `FUNCTION`, and `RETURN`, but the documentation is not (in my
opinion) very good, and to get the full picture you need to read the problem
statements for all three levels.

## Glossary

- *caller*: the function using the `CALL` macro
- *callee*: the function being called
- *nargs*: the number of arguments passed
- *nlocals*: the number of locals a function uses
- *preamble*: code in CALL that runs before it jumps to the function it's calling,
              or code in FUNCTION that runs before the function itself does
- *postscript*: code in CALL that runs after the function it's calling returns

## ABI for Programmers

If you aren't actually *writing* call/return and just want to write functions,
here is the interface.

### Caller

Push all arguments on the stack, then `CALL <function> <nargs>`. When the
function returns, all arguments have been popped and the return value is left
on top of the stack.

### Callee

Declare a function with `FUNCTION <name> <nlocals>`. When called, the global
`ARGS` will contain a pointer to the first argument, `LOCALS` will contain a
pointer to the first local, and `SP` will point just after the last local. You
can freely use the stack, but do not pop any of the locals. When done, push your
return value and `RETURN`.

## ABI Internals Overview

The ABI makes use of three globals: `ARGS`, which is stored at 0x0001 and holds
a pointer to the first argument passed to the current function; `LOCALS`, which
is stored at 0x0002 and holds a pointer to the first local declared by the
current function; and `RETVAL`, which is stored at 0x0006 and is used as
temporary storage by the `RETURN` macro (and is unused at all other times).

To call a function, the caller:

- pushes all arguments to the function onto the stack
- invokes the `CALL` macro, which:
  - pushes the current values of `ARGS` and `LOCALS` to the stack
  - pushes the return address onto the stack
  - updates `ARGS` to point to the first argument pushed
  - `JMP`s to the function being called
- The function preamble then:
  - allocates `nlocals` stack slots (either by pushing 0s or just by moving the stack pointer)
  - updates `LOCALS` to point at the first of these slots

At this point the callee can now execute; ARGS and LOCALS point to the first
argument passed by the caller and the first local allocated to the function
respectively.

When ready to return, the callee:

- pushes the return value on the stack
- invokes `RETURN`, which:
  - pops the return value from the stack and stores it in `RETVAL`
  - discards all locals, and any other values pushed by the callee, by setting
    SP to the value of `LOCALS`
  - pops the return address from the stack and `JMP`s to it

This returns control to the CALL postscript (the code after the JMP), which:

- restores the saved values of `LOCALS` and `ARGS` from the stack
- pops all arguments, restoring `SP` to the value it had before the caller started
  pushing them
- pushes the return value from `RETVAL`

And now the caller resumes execution, with its values of `ARGS` and `LOCALS` restored,
the arguments it pushed gone, and the return value on the stack.

## In detail

This is a step by step breakdown of the call process. Each step includes a stack
diagram. These diagrams grow downwards, so higher addresses are towards the bottom.


### Pre-call

Before a function makes a call, its stack might look something like this.

```
                |   ...          | ^- ARGS & LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
          SP -> | empty          | unused stack space
                |   ...          |
```

It begins by pushing arguments onto the stack, after which we have:

```
                |   ...          | ^- ARGS & LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
                | argument 0     | arguments just pushed
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
          SP -> | empty          | unused stack space
                |   ...          |
```

At this point it invokes the `CALL` macro.


### CALL: preamble

`CALL` now needs to save the `ARGS` and `LOCALS` pointers so they can be restored
after the function call, so it begins by pushing those onto the stack. It then
pushes the return address (which is going to be the address of the start of the
`CALL` postscript) so that `RETURN` knows where to find it.

```
                |   ...          | ^- ARGS & LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
                | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                | return address |
                +----------------+ - - - - - - - - - - -
          SP -> | empty          | unused stack space
                |   ...          |
```

The last thing it needs to do is point `ARGS` to the first argument -- the function
itself can't do this because it doesn't actually know how many arguments it was
called with. `CALL` does, so taking into account the three values it just pushed,
the first arg is at `(SP - 3 - nargs)`:

```
                |   ...          | ^- LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                | return address |
                +----------------+ - - - - - - - - - - -
          SP -> | empty          | unused stack space
                |   ...          |
```

The stack has not changed, but now we have a new pointer into it, and can finally
JMP into the callee.


### FUNCTION: preamble

The preamble to FUNCTION is straightforward and just needs to allocate space for
`nlocals` locals on the stack, and point the `LOCALS` pointer to the first of these.
`SP` points to the start of where the locals will go, so it can just copy that
into `LOCALS`:

```
                |   ...          |
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                | return address |
                +----------------+ - - - - - - - - - - -
LOCALS -> SP -> | empty          | unused stack space
                |   ...          |
```

And then increase the stack pointer to make room. This gives the stack as it
exists just before the actual function starts executing, annotated with
additional information about what the callee should and shouldn't do with it:

```
                |   ...          |
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          | READ/WRITE, but discarded when you return
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  | DO NOT TOUCH
                | return address | SERIOUSLY
                +----------------+ - - - - - - - - - - -
      LOCALS -> | local 0        | data owned by FUNCTION macro
                |   ...          | READ/WRITE, for this function's convenience
                | local N        |
                +----------------+ - - - - - - - - - - -
          SP -> | empty          | unused stack space
                |   ...          | do whatever you want here :)
```


### Pre-return

This is what the stack looks like just before you `RETURN`. It's pretty much
the same as before except you've presumably pushed a bunch more stuff as the
function does its work, followed by the value you want to return:

```
                |   ...          |
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                | return address |
                +----------------+ - - - - - - - - - - -
      LOCALS -> | local 0        | data owned by FUNCTION macro
                |   ...          |
                | local N        |
                +----------------+ - - - - - - - - - - -
                | things & stuff | data owned by callee
                |   ...          |
                | return value   |
                +----------------+ - - - - - - - - - - -
          SP -> |   ...          | unused stack space
```


### RETURN

This saves the return value to a safe place (the `RETVAL` global), then discards
everything added to the stack by the callee and its preamble by popping `SP` all
the way back to the start of the locals:

```
                |   ...          |
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                | return address |
                +----------------+ - - - - - - - - - - -
LOCALS -> SP -> |   ...          | unused stack space
```

It then pops the return address into `A` and jumps to it, returning control to
the `CALL` postscript.


### CALL: postscript

This is what CALL gets immediately after the function returns:

```
                |   ...          |
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
        ARGS -> | argument 0     | arguments pushed by caller
                |   ...          |
                | argument N     |
                +----------------+ - - - - - - - - - - -
                | caller ARGS    | data owned by CALL macro
                | caller LOCALS  |
                +----------------+ - - - - - - - - - - -
          SP -> |   ...          | unused stack space
```

Plus the return value stored in `RETVAL`. It needs to restore the saved `ARGS`
and `LOCALS` values by popping them from the stack, and relocate the stack pointer
back to where it was before the caller started pushing arguments:

```
                |   ...          | ^- ARGS & LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+ - - - - - - - - - - -
          SP -> |   ...          | unused stack space
```

And then finally push the return value and it's done.

```
                |   ...          | ^- ARGS & LOCALS
                | caller stack   | data owned by caller
                | frame          |
                +----------------+
                | return value   |
                +----------------+ - - - - - - - - - - -
          SP -> |   ...          | unused stack space
```
